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
internal sealed partial class ScmAccountBridgeHost : IAccountBridgeHost, IAccountBridgeConcurrentResourceReads, IDisposable
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
    private readonly DailySupportClient? _dailySupport;
    private readonly AchievementIdeaClient? _achievementIdeas;
    private readonly StarBridge.HostRuntime.Communities.CommunityClient? _communities;
    private readonly StarBridge.HostRuntime.Hangar.HangarMediaClient? _hangarMedia;
    private readonly IProfileWriteAuthorizationClient _profileAuthorization;
    private readonly ScmProfileCacheStore _profileCache;
    private readonly string _environment;
    private readonly Func<string?> _detectedGameIdentity;
    private readonly Func<string?>? _recentGameIdentity;
    private readonly Func<LocalIdentityCheckState> _lastGameIdentityCheck;
    private readonly AccountMutationGate _mutationGate;
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
    private bool _freshSignInPending;
    private readonly bool _freshSignInOnly;
    private readonly bool _retainedFirstUseOnly;
    private readonly bool _businessStartupDeferred;
    internal bool BusinessStartupDeferred => IsBusinessStartupDeferred;
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
        AccountSafetyClient? accountSafety = null,
        Func<string?>? recentGameIdentity = null,
        StarBridge.HostRuntime.Hangar.HangarMediaClient? hangarMedia = null,
        DailySupportClient? dailySupport = null,
        bool requireFreshSignIn = false,
        bool deferBusinessStartup = false,
        bool requireRetainedFirstUseSession = false,
        AchievementIdeaClient? achievementIdeas = null,
        Func<Uri, CancellationToken, Task<byte[]?>>? rsiAvatarDownload = null,
        PublicOrganizationLogoReader? publicOrganizationLogos = null)
    {
        _rsiAvatarDownload = rsiAvatarDownload ?? RsiAvatarImage.DownloadAsync;
        if (requireFreshSignIn && initialSession is not null)
            throw new ArgumentException("Fresh sign-in cannot accept a preloaded session.", nameof(initialSession));
        if (requireRetainedFirstUseSession && (requireFreshSignIn || !deferBusinessStartup || initialSession is not null))
            throw new ArgumentException("Retained resume requires a separate deferred, empty authorization owner.",
                nameof(requireRetainedFirstUseSession));
        _oauth = oauth ?? throw new ArgumentNullException(nameof(oauth));
        _mutationGate = new(RecoverInstalledFirstUseRefresh);
        _publicOrganizationLogos = publicOrganizationLogos ?? new PublicOrganizationLogoReader(_oauth);
        _compatibilityReader = compatibilityReader;
        _passwordRecovery = passwordRecovery;
        _legacyPasswordLogin = legacyPasswordLogin;
        _partyRooms = partyRooms;
        _friends = friends;
        _accountSafety = accountSafety;
        _dailySupport = dailySupport;
        _achievementIdeas = achievementIdeas;
        _communities = communities;
        _hangarMedia = hangarMedia;
        _profileAuthorization = profileAuthorization ?? oauth;
        _profileCache = profileCache ?? throw new ArgumentNullException(nameof(profileCache));
        _environment = string.IsNullOrWhiteSpace(environment)
            ? throw new ArgumentException("SCM environment is required.", nameof(environment))
            : environment.Trim();
        _detectedGameIdentity = detectedGameIdentity ??
            throw new ArgumentNullException(nameof(detectedGameIdentity));
        _recentGameIdentity = recentGameIdentity;
        _lastGameIdentityCheck = lastGameIdentityCheck ??
            (() => LocalIdentityCheckState.NotObserved);
        _session = initialSession;
        // Fresh-login and retained-resume candidates suppress ordinary restore.
        // The latter uses only its explicit Native resume operation; neither a
        // general account read nor legacy fallback may select its credentials.
        _restoreAttempted = requireFreshSignIn || requireRetainedFirstUseSession || initialSession is not null;
        _freshSignInPending = requireFreshSignIn;
        _freshSignInOnly = requireFreshSignIn;
        _retainedFirstUseOnly = requireRetainedFirstUseSession;
        _businessStartupDeferred = deferBusinessStartup;
        _generation = initialGeneration >= 0
            ? initialGeneration
            : throw new ArgumentOutOfRangeException(nameof(initialGeneration));
        _oauth.SessionInvalidated += OnSessionInvalidated;
        _oauth.StoredCredentialRejected += OnStoredCredentialRejected;
        _oauth.StationTradeDiscovered += OnStationTradeDiscovered;
    }

    public long Generation => Interlocked.Read(ref _generation);

    // Native-only display selection; never substitute it for CurrentContext.
    internal (BridgeAccountContext Owner, ScmOfflineDisplayOwner Credential)? ReadOfflineDisplaySelection()
    {
        if (_disposed || !_credentialTemporarilyUnavailable || _reauthorizationRequired ||
            _legacySession is not null || _localModeSessionLoopsStopped || IsBusinessStartupDeferred) return null;
        var selected = _oauth.ReadOfflineDisplayOwner();
        return selected is null ? null : (new(_environment, selected.Authority, selected.Subject), selected);
    }

    // Legacy reads do not refresh or replace credentials. SCM resource reads
    // still share mutable refresh state, so retain their serialized dispatch.
    public bool SupportsConcurrentReads => !_disposed && _restoreAttempted &&
        _session is null && _legacySession is not null &&
        !_reauthorizationRequired && !_credentialTemporarilyUnavailable && !_legacyRestoreUnavailable;
    public bool IsLegacyCompatibilitySession => SupportsConcurrentReads;
    // DL-129 option 3: friend and organization resource reads only. Refresh is
    // single-flight inside OAuth, and those reads commit sessions monotonically
    // (CommitSharingSession), as the sharing and fleet lanes already do.
    public bool SupportsConcurrentResourceReads => !_disposed && _restoreAttempted && _session is not null &&
        !_reauthorizationRequired && !_credentialTemporarilyUnavailable && !_localModeSessionLoopsStopped &&
        !IsBusinessStartupDeferred;

    public StarBridge.HostRuntime.Hangar.HangarAccountIdentity? HangarIdentity {
        get {
            if (_disposed) return null;
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
        IsBusinessStartupDeferred || _disposed || _localModeSessionLoopsStopped || _reauthorizationRequired || _credentialTemporarilyUnavailable || _legacyRestoreUnavailable ? null : CurrentContext;

    public IReadOnlyList<string> CurrentOverlayEntitlements
    {
        get
        {
            var session = _session;
            if (session is null && !_disposed && !_legacyRestoreUnavailable && !_reauthorizationRequired && !_credentialTemporarilyUnavailable &&
                _legacySession is { } legacy && _legacyEntitlements?.AccountId == legacy.AccountId)
                return _legacyEntitlements.ResolveActive(DateTimeOffset.UtcNow).Concat(SupportEntitlements()).Distinct().ToArray();
            return session is null || _reauthorizationRequired || _credentialTemporarilyUnavailable
                ? []
                : session.ActiveOverlayEntitlements.Concat(SupportEntitlements()).Distinct().ToArray();
        }
    }

    public event Action<long>? AccountChanged;
    internal event Action<BridgeAccountContext>? AuthenticatedSessionRetired;

    // Opaque authenticated transport only. Validation and storage belong to the
    // optional private module; this value never establishes an account context.
    internal ScmOverlayEntitlementSnapshot? ReadCurrentOfflineAppearanceSnapshot() =>
        _disposed || _reauthorizationRequired || _credentialTemporarilyUnavailable ||
        _localModeSessionLoopsStopped || IsBusinessStartupDeferred ||
        _session?.OverlayEntitlements is not { Status: "ready", Entitlements: not null,
            TemporaryEntitlements: not null, AccountId: { Length: > 0 } }
            ? null : _session.OverlayEntitlements;

    public async Task<AccountBridgeSessionProjection> GetCurrentAsync(
        CancellationToken cancellationToken)
    {
        using (var restore = AccountReadTiming.Measure(AccountReadPhase.Restore))
        {
            await EnsureRestoredAsync(cancellationToken);
            restore?.Returned();
        }
        if (IsBusinessStartupDeferred) return ProjectCurrent();
        using var business = _businessStartupDeferred ? _firstUseBusinessAdmission?.Enter(cancellationToken) : null;
        if (_businessStartupDeferred && business is null) return ProjectCurrent();
        cancellationToken = business?.Token ?? cancellationToken;
        using (var owner = AccountReadTiming.Measure(AccountReadPhase.LocalOwner))
        {
            await EnsureLocalDataOwnerAsync(cancellationToken);
            owner?.Returned();
        }
        cancellationToken.ThrowIfCancellationRequested();
        if (business is not null && !business.IsCurrent) return ProjectCurrent();
        // Runtime-owned discovery already has a cancellable session loop.
        // Root readiness still verifies storage ownership above, but must not
        // wait for this optional registration or steal it from that loop.
        if (!Volatile.Read(ref _participantLoopEnabled))
        {
            using var participation = AccountReadTiming.Measure(AccountReadPhase.Participation);
            await EnsureParticipantEnrollmentAsync(cancellationToken);
            participation?.Returned();
        }
        using var projectionTiming = AccountReadTiming.Measure(AccountReadPhase.Projection);
        EnsureParticipantLoop();
        EnsureAccountRealtime();
        EnsureRoomMembershipKeepalive();
        EnsureSupportRead();
        var projection = ProjectCurrent();
        AccountDisplayObserved?.Invoke(projection, cancellationToken);
        Volatile.Write(ref _lastFullCurrent, new(projection, LocalDataOwnerClock.GetTimestamp()));
        projectionTiming?.Returned();
        return projection;
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
            if (!IsBusinessStartupDeferred) await EnsureLocalDataOwnerAsync(loginCancellation.Token);
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
        => await LogoutCoreAsync(context, null, cancellationToken).ConfigureAwait(false);

    private async Task<bool> LogoutCoreAsync(
        BridgeAccountContext context,
        long? expectedGeneration,
        CancellationToken cancellationToken)
    {
        await _mutationGate.WaitAsync(cancellationToken);
        try
        {
            // A local-mode transition may wait behind an already queued account
            // mutation. Recheck inside the actual writer lane, not just before it.
            if (expectedGeneration is { } generation &&
                (_disposed || Generation != generation || CurrentContext != context)) return false;
            if (_session is null && LegacyContext is { } legacyContext && legacyContext == context)
            {
                _legacyPasswordLogin!.ForgetSession();
                PublishSession(null, reauthorizationRequired: false);
                return true;
            }
            var session = RequireSession(context);
            try
            {
                await _oauth.RevokeAsync(session, cancellationToken);
            }
            catch (ScmLocalCredentialRetirementException)
            {
                throw new AccountBridgeHostException("account.logout_incomplete", retryable: true);
            }
            catch (ScmRemoteRevocationException)
            {
                // RevokeAsync deletes the local DPAPI-backed credential before
                // the best-effort remote revocation request is made.
            }

            PublishSession(null, reauthorizationRequired: false);
            return true;
        }
        finally
        {
            _mutationGate.Release();
        }
    }

    public Task<AccountBridgeProfileProjection> GetProfileAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => GetProfileCoreAsync(context, cancellationToken, includeDirectory: true);

    private async Task<AccountBridgeProfileProjection> GetProfileCoreAsync(
        BridgeAccountContext context, CancellationToken cancellationToken, bool includeDirectory)
    {
        var generation = Generation;
        var session = RequireSession(context);
        var route = CurrentRoute();
        ScmProfileResult result;
        try
        {
            result = await _oauth.LoadProfileAsync(session, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            cancellationToken.ThrowIfCancellationRequested();
            lock (_realtimeGate)
            {
                RequireAccountProfileReadOwner(context, generation);
                var failure = AccountProfileReadFailures.Classify(exception);
                if (failure is null || !failure.Retryable)
                {
                    InvalidateAccountProfileCache(route);
                    if (failure is null) throw;
                    throw failure;
                }
                if (_profileReadSnapshot is { } memory && memory.Owner == context && memory.Generation == generation)
                    return ProjectProfile(memory.Profile.ToOfflineProfile(), "cache", memory.Profile.CachedAtUtc, []);
                var cached = _profileReadCacheSuppressed ? null : _profileCache.Load(route);
                if (cached is null) throw failure;
                return ProjectProfile(cached.ToOfflineProfile(), "cache", cached.CachedAtUtc, []);
            }
        }
        cancellationToken.ThrowIfCancellationRequested();
        var observedAtUtc = DateTimeOffset.UtcNow;
        lock (_realtimeGate)
        {
            RequireAccountProfileReadOwner(context, generation);
            RequireSameSession(session, result.ActiveSession);
            _session = result.ActiveSession;
            _profileReadSnapshot = new(context, generation,
                ScmCachedProfileContract.Create(route.Environment, route.Authority, result.Profile, observedAtUtc));
        }
        var directory = includeDirectory ? await LoadDirectoryAsync(cancellationToken) : [];
        cancellationToken.ThrowIfCancellationRequested();
        lock (_realtimeGate)
        {
            RequireAccountProfileReadOwner(context, generation);
            try
            {
                _profileCache.Save(route, result.Profile, observedAtUtc);
                _profileReadCacheSuppressed = false;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                ReportAccountProfileCacheFailure("write", error);
            }
            return ProjectProfile(result.Profile, "live", null, directory, includeDirectory ? null : observedAtUtc);
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
        var ownerReadSequence = BeginLocalDataOwnerRead();
        AccountBridgeCompatibilityProjection result;
        try { result = await _compatibilityReader.ReadAsync(session, cancellationToken).ConfigureAwait(false); }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or
            System.Text.Json.JsonException or InvalidOperationException or OperationCanceledException)
        {
            ObserveLocalDataOwner(context, generation, ownerReadSequence, null);
            _compatibilityReader.Reset();
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityReadUnavailable, true);
        }
        if (_disposed || Generation != generation || !ReferenceEquals(_session, session))
        {
            _compatibilityReader.Reset();
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityReadUnavailable, true);
        }
        if (!ObserveLocalDataOwner(context, generation, ownerReadSequence, result))
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityReadUnavailable, true);
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
            var ownerReadSequence = BeginLocalDataOwnerRead();
            lock (_loginGate) { _compatibilityCancellation = operation; }
            if (_disposed || generation != Generation || CurrentContext != context)
                throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityWriteUnavailable, true);
            var result = await _compatibilityReader.LinkAsync(original,
                new LegacyIdentityLinkPasswordCredential(credential.AccountName.Trim(), credential.Password), operation.Token);
            operation.Token.ThrowIfCancellationRequested();
            if (_disposed || generation != Generation || CurrentContext != context)
                throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityWriteUnavailable, true);
            if (!ObserveLocalDataOwner(context, generation, ownerReadSequence, result))
                throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityReadUnavailable, true);
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
            var generation = Generation;
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
                cancellationToken.ThrowIfCancellationRequested();
                lock (_realtimeGate)
                {
                    RequireAccountProfileReadOwner(context, generation);
                    _session = confirmed.ActiveSession;
                    var observedAtUtc = DateTimeOffset.UtcNow;
                    var route = CurrentRoute();
                    _profileReadSnapshot = new(context, generation,
                        ScmCachedProfileContract.Create(route.Environment, route.Authority, confirmed.Profile, observedAtUtc));
                    try
                    {
                        _profileCache.Save(route, confirmed.Profile, observedAtUtc);
                        _profileReadCacheSuppressed = false;
                    }
                    catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                    {
                        ReportAccountProfileCacheFailure("write-confirmed", error);
                    }
                    return ProjectProfile(confirmed.Profile, "live", null, [], observedAtUtc);
                }
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
        var generation = Generation;
        try
        {
            var result = await _oauth.LoadPersonalProfileAsync(session, cancellationToken)
                .ConfigureAwait(false);
            RequireSameSession(session, result.ActiveSession);
            _session = result.ActiveSession;
            return await WithRsiAvatarAsync(result.Profile, context, generation, cancellationToken);
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
            exception is HttpRequestException or InvalidOperationException or IOException or InvalidDataException or UnauthorizedAccessException)
        {
            var failure = PersonalProfileReadFailures.FromException(exception, cancellationToken);
            if (failure.Code is AccountBridgeStableErrors.PersonalProfileReadForbidden or AccountBridgeStableErrors.PersonalProfileDataInvalid &&
                !_disposed && generation == Generation && CurrentContext == context)
            {
                ForgetAvatarImage(context);
                AvatarDenied?.Invoke(context, generation);
            }
            throw failure;
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
            var generation = Generation;
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
                return await WithRsiAvatarAsync(result.Profile, context, generation, cancellationToken);
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

    public Task<AccountBridgeOfficialFleetProjection> GetOfficialFleetAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => ReadOfficialFleetAsync(context, cancellationToken, includeProfile: true);

    public Task<AccountBridgeOfficialFleetProjection> GetOfficialFleetIdentityAsync(
        BridgeAccountContext context, CancellationToken token) => ReadOfficialFleetAsync(context, token, includeProfile: false);

    private async Task<AccountBridgeOfficialFleetProjection> ReadOfficialFleetAsync(
        BridgeAccountContext context, CancellationToken cancellationToken, bool includeProfile)
    {
        var session = RequireSession(context);
        var generation = Generation;
        try
        {
            var result = await _oauth.LoadBootstrapAsync(session, cancellationToken)
                .ConfigureAwait(false);
            RequireFleetReadOwner(context, generation);
            RequireSameSession(session, result.ActiveSession);
            _session = result.ActiveSession;
            var projection = ProjectOfficialFleet(result.Snapshot, DateTimeOffset.UtcNow);
            FleetMembershipObserved?.Invoke(context, generation, projection.Fleet?.SourceRef);
            if (projection.Fleet is { } fleet && includeProfile) {
                try {
                    var enriched = await AddOfficialFleetProfileAsync(fleet, context, generation, cancellationToken);
                    projection = projection with { Fleet = enriched,
                        ProfileRead = new("available", DateTimeOffset.UtcNow) };
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
                catch (Exception error) {
                    // Public profile availability must not erase verified membership.
                    // Account changes, however, must still reject the entire old projection.
                    RequireFleetReadOwner(context, generation);
                    projection = projection with {
                        ProfileRead = OfficialFleet.OfficialFleetReadFailures.ForProfile(error, cancellationToken) };
                }
            }
            else if (projection.Fleet is { } identity) {
                Volatile.Write(ref _fleetPublicSource, new(context, generation, identity.SourceRef, identity.Sid));
                projection = projection with { ProfileRead = new("deferred") };
            }
            else {
                Volatile.Write(ref _fleetPublicSource, null);
            }
            return projection;
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
            exception is HttpRequestException or InvalidOperationException or IOException or UnauthorizedAccessException or
                System.Text.Json.JsonException or InvalidDataException or KeyNotFoundException or FormatException or OverflowException or
                OperationCanceledException or TimeoutException)
        {
            throw OfficialFleet.OfficialFleetReadFailures.FromException(exception, cancellationToken);
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
            lock (_realtimeGate)
            {
                _ = RequireSession(context);
                var memoryCleared = _profileReadSnapshot is { } memory &&
                    memory.Owner == context && memory.Generation == Generation;
                var diskCleared = _profileCache.Clear(CurrentRoute());
                _profileReadSnapshot = null;
                _profileReadCacheSuppressed = true;
                return Task.FromResult(diskCleared || memoryCleared);
            }
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
        return Task.FromResult(ReadCurrentGameIdentityPolicy(context));
    }

    public AccountBridgeIdentityProjection ReadCurrentGameIdentityPolicy(BridgeAccountContext context)
    {
        var relaySession = RequireRelaySession(context);
        var identity = relaySession.Scm?.AuthoritativeGameIdentity ??
            _legacyIdentity ?? new(ScmGameIdentityStatus.Unknown, null, null);
        // Compatibility login authenticates the old account, not an SCM
        // verification ceremony. Keep the comparison below: mismatch still blocks.
        if (relaySession.Scm is null && relaySession.Legacy is not null &&
            IdentityBindingPolicy.IsValidGameName(identity.Handle))
            identity = identity with { Status = ScmGameIdentityStatus.Verified };
        // Recent local identity is a cross-check, not SCM authentication. Live
        // telemetry retains its separate current-session contract.
        var detected = _detectedGameIdentity() ?? _recentGameIdentity?.Invoke();
        var assessment = detected is null
            ? IdentityBindingPolicy.Evaluate(
                identity,
                // SCM absence of a fresh log observation is not a conflict.
                // Retain the compatibility account's persisted-check semantics.
                relaySession.Scm is not null ? LocalIdentityCheckState.NotObserved : _lastGameIdentityCheck())
            : IdentityBindingPolicy.Evaluate(
                identity,
                detected);
        var state = assessment.State switch
        {
            IdentityVerificationState.Verified => "match",
            IdentityVerificationState.BindingRequired => "verificationRequired",
            IdentityVerificationState.VerificationPending => "verificationPending",
            IdentityVerificationState.Mismatch => "mismatch",
            IdentityVerificationState.AwaitingGameIdentity => "awaitingGameIdentity",
            IdentityVerificationState.ReverificationRequired => "reverifyRequired",
            IdentityVerificationState.Revoked => "revoked",
            _ => "unknown"
        };
        return new AccountBridgeIdentityProjection(
                state,
                assessment.BoundGameName,
                assessment.CanUseIdentitySensitiveNetworkWrites &&
                    (relaySession.Scm is not null || FirstUseGameIdentityReady),
                IdentityBindingPolicy.IsValidGameName(detected) ? detected?.Trim() : null,
                "unknown");
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
            AccountRestoreDisplayScope? displayScope = null;
            void ObserveDisplay(Auth.ScmRestoreDisplayRead read) => displayScope = ObserveRestoreDisplay(read);
            var wantsDisplay = WantsRestoreDisplay;
            if (wantsDisplay) _oauth.RestoreDisplayPreparing += ObserveDisplay;
            try
            {
                restored = await _oauth.TryRestoreSessionAsync(cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                // The waiter leaves independently, but its original display
                // transaction cannot retire until the shared transport drains.
                displayScope?.Dispose();
                if (displayScope is not null) await displayScope.DrainAsync().ConfigureAwait(false);
                throw;
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

            finally { if (wantsDisplay) _oauth.RestoreDisplayPreparing -= ObserveDisplay; }

            _restoreAttempted = true;
            _credentialTemporarilyUnavailable =
                _oauth.LastSessionRestoreOutcome ==
                ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable;
            _reauthorizationRequired =
                _oauth.LastSessionRestoreOutcome == ScmSessionRestoreOutcome.ReauthorizationRequired;
            if (restored is not null)
            {
                PublishRestoredSession(restored, displayScope);
            }
        }
        finally
        {
            _mutationGate.Release();
        }
    }

    private async Task<IReadOnlyList<AccountBridgeTimeZone>> LoadDirectoryAsync(
        CancellationToken cancellationToken, bool strictFailures = false)
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
        catch (Exception exception) when (strictFailures)
        {
            var failure = AccountProfileReadFailures.Directory(exception);
            if (failure is null) throw;
            throw failure;
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
                _scmDisplayCallSign ?? EmptyToNull(session.DisplayName),
                null, _scmAvatarImageData);
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
        IReadOnlyList<AccountBridgeTimeZone> directory, DateTimeOffset? observedAtUtc = null)
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
            directory,
            observedAtUtc);
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
            fleet.RankValue is < 0 or > 127)
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
                // SCM custom-rank values are not normalized RSI star counts.
                // Keep the official title; a verified star projection is unavailable.
                null),
            "live",
            resourceVersion,
            observedAtUtc);
    }

    private static AccountBridgeHostException InvalidOfficialFleetData() => new(
        AccountBridgeStableErrors.OfficialFleetDataInvalid);

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
        lock (_realtimeGate)
            PublishSessionCore(session, reauthorizationRequired, legacy, legacyUnavailable, legacyDisplayName,
                legacyIdentity, legacyAvatarImageData, legacyEntitlements);
    }

    private void PublishSessionCore(ScmOAuthSession? session, bool reauthorizationRequired,
        LegacyMigrationCredential? legacy, bool legacyUnavailable, string? legacyDisplayName,
        ScmGameIdentitySnapshot? legacyIdentity, string? legacyAvatarImageData, ScmOverlayEntitlementSnapshot? legacyEntitlements) =>
        PublishSessionState(session, reauthorizationRequired, legacy, legacyUnavailable, legacyDisplayName,
            legacyIdentity, legacyAvatarImageData, legacyEntitlements, null);

    private void PublishSessionState(ScmOAuthSession? session, bool reauthorizationRequired,
        LegacyMigrationCredential? legacy, bool legacyUnavailable, string? legacyDisplayName,
        ScmGameIdentitySnapshot? legacyIdentity, string? legacyAvatarImageData, ScmOverlayEntitlementSnapshot? legacyEntitlements,
        AccountRestoreDisplayScope? restoredDisplay)
    {
        var retiredOwner = _session is { } previousSession
            ? new BridgeAccountContext(_environment, previousSession.AuthorityId, previousSession.Subject) : null;
        var generation = ReserveSessionGeneration(); // Exhaustion cannot partially publish new identity under an old generation.
        ClearOfficialFleetProfileTargets();
        Volatile.Write(ref _fleetPublicSource, null);
        _profileReadSnapshot = null;
        _profileReadCacheSuppressed = false;
        lock (_loginGate) { _compatibilityCancellation?.Cancel(); }
        StopAccountRealtime();
        StopRoomMembershipKeepalive();
        StopParticipantLoop();
        _compatibilityReader?.Reset();
        Volatile.Write(ref _localOwnerBinding, null);
        _legacySession = legacy;
        _legacyDisplayName = legacyDisplayName;
        _legacyIdentity = legacyIdentity;
        _legacyAvatarImageData = legacyAvatarImageData;
        _scmAvatarImageData = null;
        _rsiAvatarCache = null;
        _avatarClearedOwner = null;
        Volatile.Write(ref _keptAvatarImage, null);
        _scmDisplayCallSign = null;
        _legacyEntitlements = legacyEntitlements;
        _legacyRestoreUnavailable = legacyUnavailable;
        _session = session;
        if (session is not null) _freshSignInPending = false;
        _restoreAttempted = true;
        _credentialTemporarilyUnavailable = false;
        _reauthorizationRequired = reauthorizationRequired;
        Interlocked.Exchange(ref _generation, generation);
        if (session is not null) restoredDisplay?.BindAuthenticated(ToContext(session), generation);
        _communities?.InvalidateProfileEdits();
        _communities?.InvalidateHangarEdits();
        _communities?.InvalidateRolesEdits();
        _communities?.InvalidateMemberRoleEdits();
        _communities?.InvalidateMemberRemovalEdits();
        _communities?.InvalidateOwnershipTransferEdits();
        _communities?.InvalidateInvitePreviews();
        if (retiredOwner is not null) AuthenticatedSessionRetired?.Invoke(retiredOwner);
        AccountChanged?.Invoke(generation);
        EnsureAccountRealtime();
        EnsureRoomMembershipKeepalive();
        EnsureParticipantLoop();
    }

    private void PublishLegacySession(LegacyMigrationCredential credential, bool unavailable = false, string? displayName = null,
        ScmGameIdentitySnapshot? identity = null, string? avatarImageData = null, ScmOverlayEntitlementSnapshot? entitlements = null)
    {
        // A separate Relay authority; RequireSession still rejects SCM-only operations.
        PublishSession(null, reauthorizationRequired: false, legacy: credential, legacyUnavailable: unavailable, legacyDisplayName: displayName, legacyIdentity: identity, legacyAvatarImageData: avatarImageData, legacyEntitlements: entitlements);
    }

    private void OnSessionInvalidated(OAuthPkceClient source, ScmOAuthSession invalidated)
    {
        lock (_realtimeGate)
        {
            var current = _session;
            if (current is null ||
                !current.AuthorityId.Equals(invalidated.AuthorityId, StringComparison.Ordinal) ||
                !current.Subject.Equals(invalidated.Subject, StringComparison.Ordinal) ||
                source.CurrentCredentialVersion is { } version && version != invalidated.CredentialVersion)
                return;
            // Retire the rejected owner's cache before publishing a new
            // generation makes the in-flight read's owner check fail.
            InvalidateAccountProfileCache(CurrentRoute());
            PublishSession(null, reauthorizationRequired: true);
        }
    }

    private void OnStoredCredentialRejected(string authority, string subject)
    {
        // Cold restoration has no installed session to retire. The OAuth writer
        // supplies its exact rejected owner while excluding a replacement login.
        if (!_disposed) AuthenticatedSessionRetired?.Invoke(new(_environment, authority, subject));
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
            ClearOfficialFleetProfileTargets();
            Volatile.Write(ref _fleetPublicSource, null);
            _profileReadSnapshot = null;
            _compatibilityCancellation?.Cancel();
            _legacyLoginCancellation?.Cancel();
        }
        var businessExit = RetireFirstUseBusinessAdmissionAsync();
        _ = businessExit.ContinueWith(task => _ = task.Exception, CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
        _compatibilityReader?.Dispose();
        StopParticipantLoop();
        StopAccountRealtime();
        StopRoomMembershipKeepalive();
        _activityLifetime.Cancel();
        _passwordRecovery?.Dispose();
        _legacyPasswordLogin?.Dispose();
        _partyRooms?.Dispose();
        _friends?.Dispose();
        _accountSafety?.Dispose();
        _dailySupport?.Dispose();
        _achievementIdeas?.Dispose();
        _communities?.Dispose();
        _hangarMedia?.Dispose();
        _privacyWriter?.Dispose();
        _oauth.SessionInvalidated -= OnSessionInvalidated;
        _oauth.StoredCredentialRejected -= OnStoredCredentialRejected;
        _oauth.StationTradeDiscovered -= OnStationTradeDiscovered;
        lock (_loginGate)
        {
            _loginCancellation?.Cancel();
            _loginCancellation = null;
        }

        DisposeInstalledAccountExtensions();
        DisposeMutationGateAfterFirstUseResume();
    }

    // Optional installed account modules share disposal, never credentials or
    // policy through this erased-on-public-build lifecycle seam.
    partial void DisposeInstalledAccountExtensions();
}
