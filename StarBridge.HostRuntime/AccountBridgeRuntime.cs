namespace StarBridge.HostRuntime;

using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

/// <summary>
/// Owns the single SCM OAuth/session/cache projection for the headless Host.
/// Only explicitly enabled requests reach their owning implementation.
/// </summary>
public sealed partial class AccountBridgeRuntime : IBridgeRequestDispatcher
{
    private Overlay.OverlayCommunitySource? _overlayCommunities;
    private Privacy.SharedActivityReceiver? _activityReceiver;
    public void ConfigureSharedActivity(Privacy.ISharedActivitySink sink)
    {
        if (_activityReceiver is not null) throw new InvalidOperationException("Activity receiver already configured.");
        if (_host is not Privacy.ISharedActivityReader reader) return;
        _activityReceiver = new(reader, sink, () =>
        {
            var owner = GameplayOwner();
            if (_disposed) return (null, owner.Generation, null, null);
            if (CurrentOverlaySceneMode is "room" or "auto" && CurrentRoomOverlay is { } room)
                return (owner.Context, owner.Generation, "room", room.RoomId);
            if (CurrentOverlaySceneMode == "room") return (owner.Context, owner.Generation, null, null);
            if (CurrentCommunityOverlay is { } community) return (owner.Context, owner.Generation, "organization", community.Code);
            return (owner.Context, owner.Generation, null, null);
        });
        _activityReceiver.Start();
    }
    public void ConfigureOverlayCommunitySource(string dataRoot)
    {
        if (_overlayCommunities is not null) throw new InvalidOperationException("Overlay sources already configured.");
        if (_host is Overlay.IOverlayCommunityReader reader)
            _overlayCommunities = new(() => _disposed ? (null, Generation) : GameplayOwner(), reader,
                choiceStore: new Overlay.OverlaySceneChoiceStore(dataRoot), room: () => CurrentRoomOverlay);
        if (_host is ScmAccountBridgeHost source)
            source.CommunityNameChanged = (owner, generation, code, name) =>
                _overlayCommunities?.Rename(owner, generation, code, name);
    }
    public Overlay.InformationOverlayCommunityContent? CurrentCommunityOverlay => _overlayCommunities?.ReadForDisplay();
    public string? CurrentOverlaySceneMode => _overlayCommunities?.Mode;
    private Notifications.PlayerActivityRuntime? _playerActivity;
    public bool ConfigurePlayerActivity(Notifications.PlayerActivityRuntime runtime)
    {
        if (_playerActivity is not null) throw new InvalidOperationException("Player activity already configured.");
        if (_host is not ScmAccountBridgeHost source) return false;
        _playerActivity = runtime;
        runtime.ConfigurePolicyOwner(() => _disposed ? null : GameplayOwner().Context);
        source.PlayerActivityObserved = runtime.Observe;
        source.ShouldObservePlayerActivity = runtime.ShouldObserve;
        _host.AccountChanged += ResetPlayerActivity;
        return true;
    }
    private void ResetPlayerActivity(long _) => _playerActivity?.Reset();
    private Support.GameplayDataExportDispatcher? _gameplayExport;
    public void ConfigureGameplayExportPicker(Support.IGameplayExportPicker picker, string dataRoot)
    {
        if (_gameplayExport is not null) throw new InvalidOperationException("Gameplay export already configured.");
        if (_gameplayTime is null) throw new InvalidOperationException("Gameplay runtime is unavailable.");
        _gameplayExport = new(_gameplayTime.Dispatch, GameplayOwner, picker, dataRoot);
        _host.AccountChanged += InvalidateGameplayExport;
    }
    private void InvalidateGameplayExport(long _) => _gameplayExport?.Invalidate();
    private Communities.CommunityLogoBridge? _communityLogo;
    public void ConfigureCommunityLogoPicker(Communities.ICommunityLogoPicker picker)
    {
        if (_communityLogo is not null) throw new InvalidOperationException("Organization image picker already configured.");
        _communityLogo = new(picker, () => (_host.CurrentContext, _host.Generation));
        _host.AccountChanged += InvalidateCommunityLogo;
    }
    private void InvalidateCommunityLogo(long _) => _communityLogo?.Invalidate();
    // Share the account/domain sequence source; a separate event counter would
    // cause the Flutter session to discard events from one of the producers.
    public BridgeEnvelope NotificationActivation(long generation, object payload) =>
        _dispatcher.DomainInvalidation("notificationSettings.activated", generation) with { Payload = BridgePayload.From(payload) };
    public BridgeEnvelope UpdateProgress(long generation, object payload) =>
        _dispatcher.DomainInvalidation(Updates.FlutterUpdateBridgeDispatcher.ProgressEventName, generation)
            with { Payload = BridgePayload.From(payload) };
    private static readonly HashSet<string> EnabledRequests = new(StringComparer.Ordinal)
    {
        AccountBridgeRequestNames.GetCurrent,
        AccountBridgeRequestNames.UpdateAvatar,
        AccountBridgeRequestNames.GetCompatibilityState,
        AccountBridgeRequestNames.LoginLegacy,
        AccountBridgeRequestNames.RedeemLegacyEntitlements,
        AccountBridgeRequestNames.SendPasswordResetCode,
        AccountBridgeRequestNames.ConfirmPasswordReset,
        AccountBridgeRequestNames.LinkLegacyAccount,
        AccountBridgeRequestNames.Login,
        AccountBridgeRequestNames.CancelLogin,
        AccountBridgeRequestNames.Logout,
        AccountBridgeRequestNames.GetProfile,
        AccountBridgeRequestNames.PatchPreferences,
        AccountBridgeRequestNames.ClearProfileCache,
        AccountBridgeRequestNames.GetPersonalProfile,
        "personalProfile.readVisibility",
        "personalProfile.saveVisibility",
        "communities.memberPersonalProfile",
        "users.profile",
        "users.social",
        AccountBridgeRequestNames.UpdatePersonalProfile,
        AccountBridgeRequestNames.GetLegacyProfileMigrationStatus,
        AccountBridgeRequestNames.PreviewLegacyProfileMigration,
        AccountBridgeRequestNames.ConfirmLegacyProfileMigration,
        AccountBridgeRequestNames.GetOfficialFleet,
        AccountBridgeRequestNames.GetPartyRooms,
        AccountBridgeRequestNames.ReadFriends,
        AccountBridgeRequestNames.ReadAccountSafety,
        AccountBridgeRequestNames.ReadNotificationInbox,
        AccountBridgeRequestNames.MarkNotificationInboxRead,
        AccountBridgeRequestNames.SubmitAccountAppeal,
        AccountBridgeRequestNames.ReadCommunities,
        AccountBridgeRequestNames.ExecuteCommunity,
        AccountBridgeRequestNames.GetCommunityCreationOptions,
        AccountBridgeRequestNames.CreateCommunity,
        AccountBridgeRequestNames.ReadCommunityWorkspace,
        AccountBridgeRequestNames.ReadCommunityLogs,
        AccountBridgeRequestNames.DeleteCommunityLog,
        AccountBridgeRequestNames.ReadCommunityDisband,
        AccountBridgeRequestNames.ReadCommunityChat,
        AccountBridgeRequestNames.ReadCommunityAnnouncements,
        AccountBridgeRequestNames.ReadCommunityShips,
        AccountBridgeRequestNames.ReadCommunityHangarSharing,
        AccountBridgeRequestNames.SaveCommunityHangarSharing,
        AccountBridgeRequestNames.ReadCommunityShipImage,
        AccountBridgeRequestNames.ReportCommunityShipImage,
        AccountBridgeRequestNames.ReadCommunityAnnouncementDetail,
        AccountBridgeRequestNames.ManageCommunityAnnouncements,
        AccountBridgeRequestNames.ReadCommunityChatDetail,
        AccountBridgeRequestNames.MarkCommunityChatRead,
        AccountBridgeRequestNames.SendCommunityChat,
        AccountBridgeRequestNames.DisbandCommunity,
        AccountBridgeRequestNames.ReadCommunityMedia,
        AccountBridgeRequestNames.ReadCommunityProfile,
        AccountBridgeRequestNames.ReadCommunityAdmissions,
        AccountBridgeRequestNames.ManageCommunityAdmissions,
        AccountBridgeRequestNames.SaveCommunityProfile,
        AccountBridgeRequestNames.ReadCommunityRoles,
        AccountBridgeRequestNames.SaveCommunityRoles,
        AccountBridgeRequestNames.ReadCommunityMemberRole,
        AccountBridgeRequestNames.SaveCommunityMemberRole,
        AccountBridgeRequestNames.ReadCommunityMemberRemoval,
        AccountBridgeRequestNames.RemoveCommunityMember,
        AccountBridgeRequestNames.ReadCommunityOwnershipTransfer,
        AccountBridgeRequestNames.TransferCommunityOwnership,
        AccountBridgeRequestNames.ReadCommunityOwnershipExit,
        AccountBridgeRequestNames.LeaveCommunityWithSuccessor,
        AccountBridgeRequestNames.PreviewCommunityInvite,
        AccountBridgeRequestNames.AcceptCommunityInvite,
        AccountBridgeRequestNames.SendCommunityInvite,
        AccountBridgeRequestNames.ResumeCommunityInvite,
        AccountBridgeRequestNames.ReadCommunityInvitationOutbox,
        AccountBridgeRequestNames.ExecuteFriend,
        AccountBridgeRequestNames.ReadDirectMessages,
        AccountBridgeRequestNames.SendDirectMessage,
        AccountBridgeRequestNames.MarkDirectMessagesRead,
        AccountBridgeRequestNames.ReadDirectMessagePrivacy,
        AccountBridgeRequestNames.SaveDirectMessagePrivacy,
        AccountBridgeRequestNames.ReadFriendRequestPrivacy,
        AccountBridgeRequestNames.SaveFriendRequestPrivacy,
        AccountBridgeRequestNames.ReadRecentlyPlayedPrivacy,
        AccountBridgeRequestNames.SaveRecentlyPlayedPrivacy,
        AccountBridgeRequestNames.ExecutePartyRoom,
        AccountBridgeRequestNames.GetGameIdentityPolicy
    };

    public static IReadOnlyList<string> AdvertisedCapabilities { get; } =
        Array.AsReadOnly([
            "overlayScenes.read",
            "overlayScenes.select",
            "overlayScenes.focusCommunity",
            "account.read",
            "account.avatar",
            "account.compatibility.read",
            "account.passwordRecovery",
        "account.legacyLogin",
        "account.redeemLegacyEntitlements",
            "account.legacySession",
            "account.compatibility.linkExisting",
            "account.lifecycle",
            "account.preferences.write",
            "account.profileCache.clear",
            "personalProfile.read",
            "personalProfile.write",
            "officialFleet.read",
            "partyRooms.read",
            "friends.read",
            "accountSafety.read",
            "notificationInbox.read",
            "notificationInbox.markRead",
            "accountSafety.appeal",
            "communities.read",
            "communities.commands",
            "communities.create",
            "communities.workspace",
            "communities.memberPersonalProfile",
            "users.interaction",
            "communities.logs",
            "communities.deleteLog",
            "communities.disbandPreview",
            "communities.chat",
            "communities.announcements",
            "communities.ships",
            "communities.hangarSharing",
            "communities.saveHangarSharing",
            "communities.shipImage",
            "communities.reportShipImage",
            "communities.announcementDetail",
            "communities.manageAnnouncements",
            "communities.chatDetail",
            "communities.markChatRead",
            "communities.sendChat",
            "communities.disband",
            "communities.media",
            "communities.profile",
            "communities.roles",
            "communities.saveRoles",
            "communities.memberRole",
            "communities.saveMemberRole",
            "communities.memberRemoval",
            "communities.removeMember",
            "communities.ownershipTransfer",
            "communities.transferOwnership",
            "communities.ownershipExit",
            "communities.leaveWithSuccessor",
            "communities.invites",
            "communities.sendInvite",
            "communities.admissions",
            "communities.manageAdmissions",
            "friends.commands",
            "directMessages.read",
            "directMessages.send",
            "directMessages.markRead",
            "directMessages.privacyRead",
            "directMessages.privacyWrite",
            "friendRequests.privacyRead",
            "friendRequests.privacyWrite",
            "recentlyPlayed.privacyRead",
            "recentlyPlayed.privacyWrite",
            "partyRooms.commands",
            "partyRooms.manage",
            "partyRooms.invitations",
            "partyRooms.chat",
            "partyRooms.chatAttachments",
            "hangarReader.preview",
            "hangar.local",
            "personalProfile.local",
            "privacy.local",
            "eventSharing.settings",
            "friendSharing.settings",
            "gameIdVisibility.settings",
            "privacy.publication",
        "privacy.communityScopes",
        "privacy.locationConfidence",
        "privacy.communityMemberScopes",
            "presence.visibility",
            "gameplayTime.local",
            "gameplayTime.history",
            "gameplayTime.reset",
            "gameLog.local"
        ]);

    private readonly IAccountBridgeHost _host;
    private readonly AccountBridgeDispatcher _dispatcher;
    private readonly StarBridge.HostRuntime.Hangar.HangarReaderDispatcher _hangarReader;
    private readonly Hangar.HangarAutoSync? _hangarAutoSync;
    private bool _disposed;
    private readonly Profiles.LocalPersonalProfileDispatcher? _localProfile;
    private readonly Privacy.LocalPrivacyDispatcher? _localPrivacy;
    private readonly Privacy.PrivacyPublication? _privacyPublication;
    private readonly Privacy.CommunitySharingDispatcher? _communitySharing;
    private readonly Settings.PresenceVisibilityBridge? _presenceVisibility;
    private readonly Privacy.EventSharingRuntime? _eventSharing;
    private readonly Privacy.EventSharingDispatcher? _eventSharingBridge;
    private readonly Privacy.FriendSharingRuntime? _friendSharing;
    private readonly Privacy.FriendSharingDispatcher? _friendSharingBridge;
    private readonly Privacy.GameIdSettingsDispatcher? _gameIdSettings;
    private readonly Presence.GameplayTimeRuntime? _gameplayTime;
    private readonly Presence.GameLogRuntime? _gameLog;

    internal AccountBridgeRuntime(IAccountBridgeHost host, Hangar.LocalHangarStore? localHangar = null,
        Profiles.LocalPersonalProfileStore? localProfile = null, Presence.GameplayTimeStore? gameplayTime = null,
        Presence.GameLogSettingsStore? gameLog = null, Privacy.LocalPrivacyStore? privacy = null,
        Support.LocalGameEventJournal? eventJournal = null, Settings.PresenceVisibilityStore? visibility = null)
    {
        _host = host ?? throw new ArgumentNullException(nameof(host));
        _dispatcher = new AccountBridgeDispatcher(host, EnabledRequests);
        _hangarReader = new(() => _host.HangarIdentity, localHangar);
        if (localHangar is not null)
        {
            _host.ConfigureHangarSharingSource(localHangar.Read);
            _hangarAutoSync = new(_host.UpdateSharedHangarAfterSaveAsync,
                generation => _dispatcher.PublishDomainInvalidation("hangarReader.changed", generation));
            _host.AccountChanged += _hangarAutoSync.Invalidate;
        }
        if (privacy is not null)
        {
            if (_host is IGameIdSettingsRemote gameIdRemote)
                _gameIdSettings = new(gameIdRemote, () => _disposed ? (null, _host.Generation) : GameplayOwner());
            _localPrivacy = new(privacy, () => _disposed ? (null, _host.Generation) : GameplayOwner());
            _communitySharing = new(() => _disposed ? (null, _host.Generation) : GameplayOwner(),
                _host.ReadCommunitySharingTargetsAsync, _host.ReadCommunitySharingMembersAsync);
            _privacyPublication = new(privacy, PublicationInput, _host.PublishPrivacyAsync,
                visibility: () => _presenceVisibility?.PublicationMode ?? StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Online);
            if (_host is IFriendSharingRemote friendRemote)
            {
                _friendSharing = new(friendRemote, PublicationInput, () =>
                {
                    var owner = GameplayOwner().Context;
                    return owner is not null && privacy.HasPublicationConsent(owner) &&
                        privacy.Read(owner).Settings?.PublicationEnabled == true;
                }, () => _presenceVisibility?.PublicationMode ?? StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Online);
                _friendSharingBridge = new(_friendSharing, () => _disposed ? (null, _host.Generation) : GameplayOwner());
            }
            if (eventJournal is not null && _host is IEventSharingRemote events && _host is IEventFeedRemote feed)
            {
                _eventSharing = new(events, feed, eventJournal, PublicationInput, () =>
                {
                    var owner = GameplayOwner().Context;
                    return owner is not null && privacy.HasPublicationConsent(owner) &&
                        privacy.Read(owner).Settings?.PublicationEnabled == true &&
                        (_presenceVisibility?.PublicationMode ?? StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Online)
                            is StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Online or StarBridge.Core.Presence.PlayerPresenceVisibilityMode.InGame;
                });
                _eventSharingBridge = new(_eventSharing, () => _disposed ? (null, _host.Generation) : GameplayOwner());
            }
            if (visibility is not null)
                _presenceVisibility = new(visibility, () => _disposed ? (null, _host.Generation) : GameplayOwner(),
                    async (owner, generation, change, token) =>
                    {
                        _eventSharing?.Pause();
                        _friendSharing?.Pause();
                        try
                        {
                            if (_eventSharing is not null && !await _eventSharing.StopAsync(token)) return false;
                            if (_friendSharing is not null && !await _friendSharing.StopAsync(token)) return false;
                            return await _privacyPublication.ChangeVisibilityAsync(owner, generation, change, token);
                        }
                        finally { _eventSharing?.Resume(); _friendSharing?.Resume(); }
                    }, _host.SetPresenceVisibilityAuthorityAsync,
                    () => _host.PresenceRequiresSessionConfirmation);
            _host.AccountChanged += InvalidatePrivacyPublication;
        }
        if (gameLog is not null)
        {
            _gameLog = new(gameLog, GameplayOwner, GameplayHandle, journal: eventJournal);
            _host.AccountChanged += SuspendGameLog;
        }
        if (localHangar is not null && localProfile is not null)
            _localProfile = new(localProfile, localHangar, () => (_host.CurrentContext, _host.Generation));
        if (gameplayTime is not null)
        {
            _gameplayTime = new(gameplayTime, GameplayOwner, verifiedHandle: GameplayHandle,
                historyEligibility: GameplayHistoryEligibilityAsync,
                resetRemote: _host as Presence.IGameplayTimeResetRemote,
                historyRemote: _host as Presence.IGameplayHistoryRemote);
            _host.AccountChanged += SuspendGameplayTime;
        }
    }

    private void SuspendGameplayTime(long _) => _gameplayTime?.Suspend();
    private void SuspendGameLog(long _) => _gameLog?.Suspend();
    private void InvalidatePrivacyPublication(long _) => _privacyPublication?.Invalidate();

    private Privacy.PrivacyPublicationInput? PublicationInput()
    {
        var owner = GameplayOwner();
        var identity = _host.HangarIdentity;
        var handle = GameplayHandle();
        if (_disposed || owner.Context is null || identity is null || handle is null) return null;
        var check = _gameLog?.IdentityPolicyState ?? StarBridge.Core.Identity.LocalIdentityCheckState.NotObserved;
        var confirmed = check == StarBridge.Core.Identity.LocalIdentityCheckState.Match &&
            StarBridge.Core.Identity.IdentityBindingPolicy.Evaluate(identity.Identity, check).CanUseIdentitySensitiveNetworkWrites;
        return new(owner.Context, owner.Generation, handle, confirmed, ConfirmedGameVersion, CurrentGameSession);
    }

    public async Task<bool> StopPrivacyPublicationAsync(CancellationToken token = default)
    {
        var events = _eventSharing is null || await _eventSharing.StopForShutdownAsync(token);
        var friends = _friendSharing is null || await _friendSharing.StopAsync(token, shutdown: true);
        var realtime = _privacyPublication is null || await _privacyPublication.StopAsync(token);
        return events && friends && realtime;
    }

    private string? GameplayHandle()
    {
        var identity = _host.HangarIdentity;
        if (identity is null || identity.Account != _host.GameplayTimeContext || identity.Generation != _host.Generation)
            return null;
        return StarBridge.Core.Hangar.RsiHangarIdentityPolicy.DisplayHandle(identity.Identity);
    }

    private async Task<Presence.GameplayHistoryEligibility> GameplayHistoryEligibilityAsync(
        BridgeAccountContext owner, CancellationToken token)
    {
        if (_host is Presence.IGameplayHistoryRemote remote)
        {
            var state = await remote.ReadAsync(owner, token).ConfigureAwait(false);
            // A reset/import receipt belongs to the S2 statistics authority, not the
            // separately migrated presentation profile. Never let old profile data
            // grant a second import or hide a freshly reset account's opportunity.
            if (state.HistoryImportOperationId is not null || state.HistoryImportedAt is not null)
                return new("imported", state.HistoryImportedAt);
            if (state.LastOperationId is not null)
                return new(state.HistoricalPlayTimeSeconds == 0 ? "available" : "unavailable");
        }
        var profile = await _host.GetPersonalProfileAsync(owner, token).ConfigureAwait(false);
        var statistics = profile.GameplayStatistics;
        string? migrationState = null;
        if (statistics is null)
        {
            // Reuse existing migration metadata; no new SCM scope or remote write.
            var migration = await _host.MigrateLegacyProfileAsync(owner, "status", null, false, token).ConfigureAwait(false);
            migrationState = migration.State;
        }
        // Missing/partial legacy statistics are not proof of an unused import opportunity.
        var assessment = StarBridge.Core.Profiles.GameplayHistoryImportPolicy.Evaluate(statistics, migrationState);
        return new(assessment.State, assessment.ImportedAt);
    }

    private (BridgeAccountContext? Context, long Generation) GameplayOwner()
    {
        var generation = _host.Generation;
        var context = _host.GameplayTimeContext;
        return (generation == _host.Generation ? context : null, generation);
    }

    public long Generation => _host.Generation;
    public Uri? DiagnosticsRelayUri { get; private set; }
    public string? ConfirmedGameVersion => _gameLog?.ConfirmedVersion;
    public string? SelectedGameLogPathForDiagnostics => _gameLog?.SelectedPathForDiagnostics;
    public Presence.GameLogSessionSnapshot CurrentGameSession =>
        _gameLog?.CurrentSession ?? Presence.GameLogSessionSnapshot.Empty;
    public IReadOnlyList<string> CurrentOverlayEntitlements =>
        _host.CurrentOverlayEntitlements;

    public Overlay.InformationOverlayRoomContent? CurrentRoomOverlay => _host.CurrentRoomOverlay;

    public static AccountBridgeRuntime CreateIsolatedSandboxShell() =>
        new(new EnvironmentLockedAccountBridgeHost("hangar-sandbox"));

    public event Action<BridgeEnvelope>? EventReady
    {
        add => _dispatcher.EventReady += value;
        remove => _dispatcher.EventReady -= value;
    }

    public static async Task<AccountBridgeRuntime> CreateDefaultAsync(
        Func<string?>? detectedGameIdentity = null,
        CancellationToken cancellationToken = default,
        Support.LocalGameEventJournal? eventJournal = null)
    {
        var configuration = await ScmRuntimeConfiguration.ResolveDefaultAsync(
                HostDataRoot.CurrentRoot,
                cancellationToken)
            .ConfigureAwait(false);
        if (!configuration.AccountAccessEnabled)
        {
            return new AccountBridgeRuntime(
                new EnvironmentLockedAccountBridgeHost(configuration.EnvironmentId));
        }

        var http = new ScmHttpClient();
        var deviceId = ScmDeviceId.LoadOrCreate();
        var oauth = new OAuthPkceClient(
            http,
            new WindowsTokenVault(configuration.TokenVaultPath),
            configuration.OAuthOptions,
            () => deviceId);
        AccountBridgeRuntime? runtime = null;
        runtime = new AccountBridgeRuntime(
            new ScmAccountBridgeHost(
                oauth,
                new ScmProfileCacheStore(),
                configuration.EnvironmentId,
                detectedGameIdentity ?? (() => runtime?._gameLog?.DetectedHandle),
                lastGameIdentityCheck: detectedGameIdentity is null
                    ? () => runtime?._gameLog?.IdentityPolicyState ??
                            StarBridge.Core.Identity.LocalIdentityCheckState.NotObserved
                    : null,
                partyRooms: new PartyRooms.PartyRoomReader(configuration.LegacyRelayBaseUri),
                friends: new Friends.FriendsReader(configuration.LegacyRelayBaseUri),
                accountSafety: new AccountSafetyClient(configuration.LegacyRelayBaseUri),
                communities: new Communities.CommunityClient(configuration.LegacyRelayBaseUri),
                compatibilityReader: S2CompatibilityReader.Create(http, oauth, configuration),
                passwordRecovery: new LegacyPasswordRecoveryClient(configuration.LegacyRelayBaseUri),
                legacyPasswordLogin: new LegacyPasswordLoginClient(configuration.LegacyRelayBaseUri,
                    new WindowsLegacyMigrationCredentialStore(configuration.LegacyMigrationCredentialPath),
                    sessionStore: new WindowsLegacyMigrationCredentialStore(
                        configuration.LegacyMigrationCredentialPath + ".active-" +
                        Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
                            System.Text.Encoding.UTF8.GetBytes(configuration.LegacyRelayBaseUri.AbsoluteUri)))[..16] + ".dat"))),
            new Hangar.LocalHangarStore(HostDataRoot.CurrentRoot),
            new Profiles.LocalPersonalProfileStore(HostDataRoot.CurrentRoot),
            new Presence.GameplayTimeStore(HostDataRoot.CurrentRoot),
            new Presence.GameLogSettingsStore(HostDataRoot.CurrentRoot),
            new Privacy.LocalPrivacyStore(HostDataRoot.CurrentRoot), eventJournal,
            new Settings.PresenceVisibilityStore(HostDataRoot.CurrentRoot));
        if (runtime._host is ScmAccountBridgeHost scm)
            scm.ConfigurePrivacyWriter(new Privacy.PrivacyRelayWriter(configuration.LegacyRelayBaseUri));
        runtime.DiagnosticsRelayUri = configuration.LegacyRelayBaseUri;
        return runtime;
    }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        if (_eventSharingBridge is not null && request.Name is "eventSharing.read" or "eventSharing.save")
            return await _eventSharingBridge.DispatchAsync(request, cancellationToken);
        if (_friendSharingBridge is not null && request.Name is "friendSharing.read" or "friendSharing.save")
            return await _friendSharingBridge.DispatchAsync(request, cancellationToken);
        if (_gameIdSettings is not null && request.Name is "gameIdVisibility.read" or "gameIdVisibility.save")
            return await _gameIdSettings.DispatchAsync(request, cancellationToken);
        if (_overlayCommunities is not null && request.Name is "overlayScenes.read" or "overlayScenes.select" or "overlayScenes.focusCommunity")
            return await _overlayCommunities.DispatchAsync(request, cancellationToken).ConfigureAwait(false);
        if (_communityLogo is not null && Communities.CommunityLogoBridge.Requests.Contains(request.Name))
            return await _communityLogo.DispatchAsync(request, cancellationToken).ConfigureAwait(false);
        if (_communitySharing is not null && request.Name is "privacy.communityTargets" or "privacy.communityMembers")
            return await _communitySharing.DispatchAsync(request, cancellationToken).ConfigureAwait(false);
        if (_presenceVisibility is not null && request.Name is "presence.read" or "presence.set")
            return await _presenceVisibility.DispatchAsync(request, cancellationToken).ConfigureAwait(false);
        if (_privacyPublication is not null && request.Name is "privacy.publicationStatus" or "privacy.applyPublication" or "privacy.stopPublication")
        {
            try
            {
                BridgeEnvelopeValidator.ValidateWireShape(request);
                BridgeEnvelopeValidator.RequireCurrentVersion(request);
                var owner = GameplayOwner();
                if (_disposed || request.MessageType != BridgeMessageTypes.Request || owner.Context is null ||
                    request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation)
                    throw new Privacy.LocalPrivacyException("privacy_publication.account_changed");
                Privacy.LocalPrivacyStore.RejectDuplicates(request.Payload);
                if (request.Payload.GetRawText().Length > 1024 || request.Payload.GetProperty("schemaVersion").GetInt32() != 1 ||
                    request.Payload.EnumerateObject().Any(p => p.Name != "schemaVersion" &&
                        !(request.Name == "privacy.applyPublication" && p.Name == "expectedRevision")))
                    throw new Privacy.LocalPrivacyException("privacy_publication.invalid_request");
                if (request.Name == "privacy.applyPublication")
                    await _privacyPublication.ApplyAsync(owner.Context, owner.Generation,
                        request.Payload.GetProperty("expectedRevision").GetInt64(), cancellationToken).ConfigureAwait(false);
                else if (request.Name == "privacy.stopPublication")
                {
                    _eventSharing?.Pause();
                    _friendSharing?.Pause();
                    try
                    {
                        var eventsStopped = _eventSharing is null || await _eventSharing.StopAsync(cancellationToken);
                        var friendsStopped = _friendSharing is null || await _friendSharing.StopAsync(cancellationToken);
                        await _privacyPublication.StopAsync(cancellationToken, explicitRequest: true).ConfigureAwait(false);
                        if (!eventsStopped || !friendsStopped) throw new Privacy.LocalPrivacyException("privacy_publication.withdrawal_pending");
                    }
                    finally { _eventSharing?.Resume(); _friendSharing?.Resume(); }
                }
                if (GameplayOwner() != owner) throw new Privacy.LocalPrivacyException("privacy_publication.account_changed");
                return new(BridgeEnvelope.Response(request, _privacyPublication.StatusFor(owner.Context)), []);
            }
            catch (Privacy.LocalPrivacyException error)
            { return new(BridgeEnvelope.ErrorResponse(request, new(error.Code, "Privacy publication operation failed.", true)), []); }
            catch (Exception error) when (error is System.Text.Json.JsonException or InvalidOperationException or KeyNotFoundException or
                FormatException or OverflowException or BridgeProtocolException)
            { return new(BridgeEnvelope.ErrorResponse(request, new("privacy_publication.invalid_request", "Privacy publication request is invalid.")), []); }
        }
        if (request.Name == AccountBridgeRequestNames.Logout && request.MessageType == BridgeMessageTypes.Request &&
            request.AccountContext == _host.CurrentContext &&
            request.SessionGeneration == _host.Generation)
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            await StopPrivacyPublicationAsync(cancellationToken).ConfigureAwait(false);
        }
        if (_gameLog is not null && request.Name.StartsWith("gameLog.", StringComparison.Ordinal))
            return await Task.Run(() => _gameLog.Dispatch(request, cancellationToken), cancellationToken).ConfigureAwait(false);
        if (request.Name.StartsWith("hangarReader.", StringComparison.Ordinal))
        {
            var batch = _hangarReader.Dispatch(request, cancellationToken);
            if (request.Name == "hangarReader.save" && batch.Response.Status == BridgeResponseStatuses.Ok)
            {
                // A committed local import remains successful if its separate
                // organization publication is unavailable. Never roll it back.
                if (batch.Response.Payload.TryGetProperty("partial", out var partial) && !partial.GetBoolean())
                {
                    _ = _hangarAutoSync?.Queue(request.AccountContext!, request.SessionGeneration,
                        batch.Response.Payload.GetProperty("revision").GetInt64());
                }
                if (request.SessionGeneration != _host.Generation)
                    return new(BridgeEnvelope.ErrorResponse(request, new("hangar.account_changed", "The account changed.")), []);
                return new(batch.Response, [_dispatcher.DomainInvalidation("hangarReader.changed", request.SessionGeneration)]);
            }
            return batch;
        }
        if (_localProfile is not null && request.Name is "personalProfile.localRead" or "personalProfile.localSave")
            return _localProfile.Dispatch(request, cancellationToken);
        if (_localPrivacy is not null && request.Name is "privacy.localRead" or "privacy.localSave")
        {
            var batch = _localPrivacy.Dispatch(request, cancellationToken);
            if (request.Name == "privacy.localSave" && batch.Response.Error is null && _privacyPublication is not null)
                // Local durability must not time out behind a network acknowledgement.
                // The publisher reports its own progress and handles retry/withdrawal.
                _ = _privacyPublication.TickAsync();
            return batch;
        }
        if (_gameplayExport is not null && request.Name == Support.GameplayDataExportDispatcher.RequestName)
            return await _gameplayExport.DispatchAsync(request, cancellationToken).ConfigureAwait(false);
        if (_gameplayTime is not null && request.Name.StartsWith("gameplayTime.", StringComparison.Ordinal))
            return request.Name.StartsWith("gameplayTime.reset", StringComparison.Ordinal) && _host is Presence.IGameplayTimeResetRemote resetRemote
                ? await _gameplayTime.DispatchResetAsync(request, resetRemote, cancellationToken).ConfigureAwait(false)
                : request.Name.StartsWith("gameplayTime.history", StringComparison.Ordinal)
                ? await _gameplayTime.DispatchHistoryAsync(request, cancellationToken).ConfigureAwait(false)
                : _gameplayTime.Dispatch(request, cancellationToken);
        if (!EnabledRequests.Contains(request.Name))
        {
            return new BridgeDispatchBatch(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(
                        BridgeErrorCodes.CapabilityUnavailable,
                        "The requested account capability is not available.")),
                []);
        }

        var result = await _dispatcher
            .DispatchAsync(request, cancellationToken)
            .ConfigureAwait(false);
        return new BridgeDispatchBatch(result.Response, result.Events);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _host.AccountChanged -= InvalidateCommunityNotifications;
        _communityNotifications?.Dispose();
        _overlayCommunities?.Dispose();
        if (_hangarAutoSync is not null) _host.AccountChanged -= _hangarAutoSync.Invalidate;
        _hangarAutoSync?.Dispose();
        _host.AccountChanged -= ResetPlayerActivity;
        if (_host is ScmAccountBridgeHost activitySource) {
            activitySource.PlayerActivityObserved = null;
            activitySource.ShouldObservePlayerActivity = null;
        }
        _playerActivity?.Reset();
        _host.AccountChanged -= InvalidateGameplayExport;
        _gameplayExport?.Dispose();
        _host.AccountChanged -= InvalidateCommunityLogo;
        _communityLogo?.Dispose();
        _host.AccountChanged -= InvalidatePrivacyPublication;
        _privacyPublication?.Dispose();
        _presenceVisibility?.Dispose();
        _eventSharing?.Dispose();
        _friendSharing?.Dispose();
        _activityReceiver?.Dispose();
        _host.AccountChanged -= SuspendGameplayTime;
        _host.AccountChanged -= SuspendGameLog;
        _gameLog?.Dispose();
        _gameplayTime?.Dispose();
        _dispatcher.Dispose();
        _hangarReader.Dispose();
        if (_host is IDisposable disposableHost)
        {
            disposableHost.Dispose();
        }
    }
}
