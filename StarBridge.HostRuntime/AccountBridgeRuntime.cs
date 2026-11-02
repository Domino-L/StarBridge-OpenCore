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
    private readonly Lifecycle.AsyncWorkRetirement _requestRetirement = new();
    private Overlay.OverlayCommunitySource? _overlayCommunities;
    private bool _moduleCommunityDriverEnabled;
    private Privacy.SharedActivityReceiver? _activityReceiver;
    public void ConfigureSharedActivity(Privacy.ISharedActivitySink sink)
    {
        using var configuration = EnterAccountBusinessConfiguration();
        if (configuration is null) throw new InvalidOperationException("Account background work has retired.");
        if (_activityReceiver is not null) throw new InvalidOperationException("Activity receiver already configured.");
        if (_host is not Privacy.ISharedActivityReader reader) return;
        _activityReceiver = new(reader, sink, CaptureSharedActivityContext);
        if (!_firstUseCandidate) _activityReceiver.Start();
    }
    internal Privacy.SharedActivitySubscription CaptureSharedActivityContext()
    {
        var owner = GameplayOwner();
        if (_disposed) return new(null, owner.Generation, null, null);
        if (_liveOverlaySink?.HasDisplayDemand == false)
        {
            _overlayCommunities?.SuspendDisplayDemand();
            return new(null, owner.Generation, null, null);
        }
        if (_liveOverlaySink?.ModuleDemand is { } demand)
            return CaptureModuleActivityContext(demand, owner.Context, owner.Generation);
        if (CurrentOverlaySceneMode is "room" or "auto" && CurrentRoomOverlay is { } room)
            return new(owner.Context, owner.Generation, "room", room.RoomId, room.ContinuityId);
        if (CurrentOverlaySceneMode == "room") return new(owner.Context, owner.Generation, null, null);
        if (_overlayCommunities?.IsFleetSelected == false && _overlayCommunities.Read() is { } community)
            return new(owner.Context, owner.Generation, "organization", community.Code, community.ContinuityId);
        return new(owner.Context, owner.Generation, null, null);
    }
    public void ConfigureOverlayCommunitySource(string dataRoot) => ConfigureOverlayCommunitySource(dataRoot, true);
    internal void ConfigureOverlayCommunitySource(string dataRoot, bool startDriver)
    {
        using var configuration = EnterAccountBusinessConfiguration();
        if (configuration is null) throw new InvalidOperationException("Account background work has retired.");
        if (_overlayCommunities is not null) throw new InvalidOperationException("Overlay sources already configured.");
        _moduleCommunityDriverEnabled = startDriver;
        if (_host is Overlay.IOverlayCommunityReader reader)
        {
            _overlayCommunities = new(() => _disposed ? (null, Generation) : GameplayOwner(), reader, startDriver && !_firstUseCandidate,
                choiceStore: new Overlay.OverlaySceneChoiceStore(dataRoot), room: () => CurrentRoomOverlay, prepareWhenIdle: true,
                presetRoomTrigger: () => (_host as ScmAccountBridgeHost)?.ReadOverlayPresetTrigger() ?? (false, null),
                moduleDemand: () => _liveOverlaySink?.ModuleDemand,
                moduleRoomLease: () => (_host as ScmAccountBridgeHost)?.CurrentRoomOverlaySource?.Lease);
            _overlayCommunities.DirectoryMembershipConfirmed += (owner, generation, codes) =>
                _moduleSourceBudget.ConfirmCommunities(Overlay.OverlaySceneChoiceStore.Hash(owner), generation, codes);
            _overlayCommunities.MembershipRevoked += (owner, generation, code) =>
                _moduleSourceBudget.RevokeCommunity(Overlay.OverlaySceneChoiceStore.Hash(owner), generation, code);
        }
        if (_host is ScmAccountBridgeHost source)
        {
            source.FleetMembershipObserved = (owner, generation, sourceRef) =>
            {
                _overlayCommunities?.ObserveFleetMembership(owner, generation, sourceRef);
                _moduleSourceBudget.ConfirmFleet(Overlay.OverlaySceneChoiceStore.Hash(owner), generation, sourceRef is not null);
            };
            source.CommunityNameChanged = (owner, generation, code, name) =>
                _overlayCommunities?.Rename(owner, generation, code, name);
            source.CommunityRosterObserved = (owner, generation, sequence, startedAt, roster) =>
                _overlayCommunities?.ObserveWorkspace(owner, generation, sequence, startedAt, roster);
            source.CommunityDirectoryObserved = (owner, generation, sequence, startedAt, rosters) =>
                _overlayCommunities?.ObserveDirectory(owner, generation, sequence, startedAt, rosters);
            source.CommunityRosterRevoked = (owner, generation, sequence, code) =>
                _overlayCommunities?.RevokeWorkspace(owner, generation, sequence, code);
        }
    }
    public Overlay.InformationOverlayCommunityContent? CurrentCommunityOverlay => _overlayCommunities?.ReadForDisplay();
    public Task PrepareCommunityOverlayAsync(CancellationToken cancellation) =>
        _overlayCommunities?.PrepareForDisplayAsync(cancellation) ?? Task.CompletedTask;
    // The legacy native entry renders both organization families through the
    // existing community projection. The Bridge retains the distinct fleet mode.
    public string? CurrentOverlaySceneMode => _overlayCommunities?.Mode is { } mode ? mode == "fleet" ? "community" : mode : null;
    public Overlay.OverlayPresetTrigger? CurrentOverlayPresetTrigger =>
        _disposed ? null : _overlayCommunities?.CurrentPresetTrigger();
    public (string? OwnerKey, long Generation) CurrentOverlaySourceScope
    {
        get
        {
            var owner = GameplayOwner();
            return (_disposed || owner.Context is null ? null : Overlay.OverlaySceneChoiceStore.Hash(owner.Context), owner.Generation);
        }
    }
    public Overlay.InformationOverlayRosterPreferences CurrentOverlayRosterPreferences =>
        _overlayCommunities?.RosterPreferences ?? Overlay.InformationOverlayRosterPreferences.Empty;
    private Notifications.PlayerActivityRuntime? _playerActivity;
    private bool _ownsPlayerActivity;
    public bool ConfigurePlayerActivity(Notifications.PlayerActivityRuntime runtime) =>
        ConfigurePlayerActivityCore(runtime, ownsRuntime: false);
    private bool ConfigurePlayerActivityCore(Notifications.PlayerActivityRuntime runtime, bool ownsRuntime)
    {
        using var configuration = EnterAccountBusinessConfiguration();
        if (configuration is null) return false;
        if (_playerActivity is not null) throw new InvalidOperationException("Player activity already configured.");
        if (_host is not ScmAccountBridgeHost source) return false;
        _playerActivity = runtime;
        _ownsPlayerActivity = ownsRuntime;
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
        using var configuration = EnterAccountBusinessConfiguration();
        if (configuration is null) throw new InvalidOperationException("Account background work has retired.");
        if (_gameplayExport is not null) throw new InvalidOperationException("Gameplay export already configured.");
        if (_gameplayTime is null) throw new InvalidOperationException("Gameplay runtime is unavailable.");
        _gameplayExport = new(_gameplayTime.Dispatch, GameplayOwner, picker, dataRoot);
        _host.AccountChanged += InvalidateGameplayExport;
    }
    private void InvalidateGameplayExport(long _) => _gameplayExport?.Invalidate();
    private Communities.CommunityLogoBridge? _communityLogo;
    public void ConfigureCommunityLogoPicker(Communities.ICommunityLogoPicker picker)
    {
        using var configuration = EnterAccountBusinessConfiguration();
        if (configuration is null) throw new InvalidOperationException("Account background work has retired.");
        if (_communityLogo is not null) throw new InvalidOperationException("Organization image picker already configured.");
        _communityLogo = new(picker, () => (_host.CurrentContext, _host.Generation));
        _host.AccountChanged += InvalidateCommunityLogo;
    }
    private void InvalidateCommunityLogo(long _) => _communityLogo?.Invalidate();
    private Hangar.HangarImageDraftBridge? _hangarImages;
    private readonly Hangar.LocalHangarStore? _localHangarStore;
    public void ConfigureHangarImagePicker(Communities.ICommunityLogoPicker picker)
    {
        using var configuration = EnterAccountBusinessConfiguration();
        if (configuration is null) throw new InvalidOperationException("Account background work has retired.");
        if (_hangarImages is not null) throw new InvalidOperationException("Hangar image picker already configured.");
        if (_localHangarStore is null) { picker.Dispose(); return; }
        _hangarImages = new(picker, () => (_host.CurrentContext, _host.Generation), _localHangarStore.Read, _localHangarStore);
        _host.AccountChanged += InvalidateHangarImages;
    }
    private void InvalidateHangarImages(long _) => _hangarImages?.Invalidate();
    // Share the account/domain sequence source; a separate event counter would
    // cause the Flutter session to discard events from one of the producers.
    public BridgeEnvelope NotificationActivation(long generation, object payload) =>
        _dispatcher.DomainInvalidation("notificationSettings.activated", generation) with { Payload = BridgePayload.From(payload) };
    public BridgeEnvelope SocialNotification(long generation, object payload) =>
        _dispatcher.DomainInvalidation("notificationSettings.social", generation) with { Payload = BridgePayload.From(payload) };
    public BridgeEnvelope HostEvent(long generation, string name, object payload) =>
        _dispatcher.DomainInvalidation(name, generation) with { Payload = BridgePayload.From(payload) };
    public BridgeEnvelope MenuHotkeyIntent(long generation, object payload) =>
        _dispatcher.DomainInvalidation(Overlay.MenuHotkeyBridgeDispatcher.IntentEvent, generation) with { Payload = BridgePayload.From(payload) };
    private Overlay.MenuHotkeyBridgeDispatcher? _menuHotkeys;
    public void ConfigureMenuHotkeys(Overlay.MenuHotkeyBridgeDispatcher dispatcher)
    {
        if (_menuHotkeys is not null) throw new InvalidOperationException("Menu hotkeys already configured.");
        _menuHotkeys = dispatcher;
        _host.AccountChanged += InvalidateMenuHotkeys;
    }
    private void InvalidateMenuHotkeys(long _) => _menuHotkeys?.Invalidate();
    public async Task<Notifications.GameIdentityNotificationPolicy> ReadGameIdentityNotificationPolicyAsync(
        BridgeAccountContext context, CancellationToken token)
    {
        var generation = _host.Generation;
        if (_disposed || context != _host.CurrentContext)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.GameIdentityReadUnavailable);
        var policy = await _host.GetGameIdentityPolicyAsync(context, token);
        token.ThrowIfCancellationRequested();
        if (_disposed || generation != _host.Generation || context != _host.CurrentContext)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.GameIdentityReadUnavailable);
        return new(policy.State, policy.AuthoritativeHandle, policy.DetectedHandle);
    }
    public bool IsGameIdentityNotificationCurrent(BridgeAccountContext context, Notifications.GameIdentityNotificationPolicy expected)
    {
        try
        {
            var generation = _host.Generation;
            if (_disposed || context != _host.CurrentContext) return false;
            var policy = _host.ReadCurrentGameIdentityPolicy(context);
            return !_disposed && generation == _host.Generation && context == _host.CurrentContext &&
                policy is { State: "mismatch" } &&
                string.Equals(policy.AuthoritativeHandle?.Trim(), expected.AuthoritativeHandle?.Trim(), StringComparison.OrdinalIgnoreCase) &&
                string.Equals(policy.DetectedHandle?.Trim(), expected.DetectedHandle?.Trim(), StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }
    public BridgeEnvelope UpdateProgress(long generation, object payload) =>
        _dispatcher.DomainInvalidation(Updates.FlutterUpdateBridgeDispatcher.ProgressEventName, generation)
            with { Payload = BridgePayload.From(payload) };
    private static readonly HashSet<string> EnabledRequests = new(StringComparer.Ordinal)
    {
        "imageCache.open", "imageCache.read", "imageCache.beginWrite", "imageCache.append",
        "imageCache.commit", "imageCache.reject", "imageCache.close",
        AccountBridgeRequestNames.GetCurrent,
        AccountBridgeRequestNames.UpdateAvatar,
        AccountBridgeRequestNames.ReadAvatar,
        AccountBridgeRequestNames.UpdateCallSign,
        GameIdentityBridge.RequestCode,
        GameIdentityBridge.Verify,
        GameIdentityBridge.OpenProfile,
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
        AccountBridgeRequestNames.ReadProfileDisplayCache,
        AccountBridgeRequestNames.GetProfileDisplayData,
        AccountBridgeRequestNames.GetProfileTimeZoneDirectory,
        AccountBridgeRequestNames.PatchPreferences,
        AccountBridgeRequestNames.ClearProfileCache,
        AccountBridgeRequestNames.GetPersonalProfile,
        "personalProfile.readVisibility",
        "personalProfile.saveVisibility",
        "personalProfile.readBackground",
        "personalProfile.saveBackground",
        "communities.memberPersonalProfile",
        "users.profile",
        "users.social",
        AccountBridgeRequestNames.UpdatePersonalProfile,
        "personalProfile.updatePresentation",
        AccountBridgeRequestNames.GetLegacyProfileMigrationStatus,
        AccountBridgeRequestNames.PreviewLegacyProfileMigration,
        AccountBridgeRequestNames.ConfirmLegacyProfileMigration,
        AccountBridgeRequestNames.GetOfficialFleet,
        AccountBridgeRequestNames.GetOfficialFleetMembers,
            AccountBridgeRequestNames.ReadOfficialFleetShips,
            AccountBridgeRequestNames.ReadOfficialFleetShipImage,
            AccountBridgeRequestNames.ReportOfficialFleetShipImage,
            AccountBridgeRequestNames.ReadOfficialFleetShipImageReportStatus,
        AccountBridgeRequestNames.GetOfficialFleetRuntimeMembers,
        AccountBridgeRequestNames.WaitOfficialFleetRuntimeActivity,
            AccountBridgeRequestNames.ReadOfficialFleetHangarSharing,
            AccountBridgeRequestNames.ReadOfficialFleetHangarSharingPage,
            AccountBridgeRequestNames.SaveOfficialFleetHangarSharing,
        AccountBridgeRequestNames.OfficialFleetCommunication,
        AccountBridgeRequestNames.ReadOfficialFleetGovernanceContext,
        AccountBridgeRequestNames.ReadOfficialFleetRankPolicy,
        AccountBridgeRequestNames.WriteOfficialFleetRankPolicy,
        AccountBridgeRequestNames.UpdateOfficialFleetRolePermissions,
        AccountBridgeRequestNames.ReadOfficialFleetMemberRoles,
        AccountBridgeRequestNames.AssignOfficialFleetRole,
        AccountBridgeRequestNames.RevokeOfficialFleetRole,
        AccountBridgeRequestNames.ReadOfficialFleetGovernanceAudit,
        AccountBridgeRequestNames.ReadOfficialFleetGovernanceOutcome,
        AccountBridgeRequestNames.ActivateOfficialFleetGovernance,
        AccountBridgeRequestNames.RevokeOfficialFleetGovernanceActivation,
        AccountBridgeRequestNames.ReadOfficialFleetRoleTemplates,
        AccountBridgeRequestNames.ManageOfficialFleetRoleTemplates,
        AccountBridgeRequestNames.ReadOfficialFleetRoleTemplateOutcome,
        AccountBridgeRequestNames.ReadOfficialFleetAnnouncementEditor,
        AccountBridgeRequestNames.ManageOfficialFleetAnnouncements,
        AccountBridgeRequestNames.ReadOfficialFleetAnnouncementOutcome,
        AccountBridgeRequestNames.WaitOfficialFleetActivity,
        AccountBridgeRequestNames.OfficialFleetRally,
        AccountBridgeRequestNames.GetOfficialFleetIdentity,
        AccountBridgeRequestNames.GetOfficialFleetPublicProfile,
        AccountBridgeRequestNames.GetPartyRooms,
        AccountBridgeRequestNames.ReadFriends,
        AccountBridgeRequestNames.ReadFriendsPage,
        AccountBridgeRequestNames.ReadAccountSafety,
        "account.supportRead",
        "account.supportClaim",
        "account.achievementIdeaSubmit",
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
        AccountBridgeRequestNames.WaitSocialActivity,
        AccountBridgeRequestNames.WaitCommunityActivity,
        AccountBridgeRequestNames.SendDirectMessage,
        AccountBridgeRequestNames.MarkDirectMessagesRead,
        AccountBridgeRequestNames.ReadDirectMessagePrivacy,
        AccountBridgeRequestNames.SaveDirectMessagePrivacy,
        AccountBridgeRequestNames.ReadFriendRequestPrivacy,
        AccountBridgeRequestNames.SaveFriendRequestPrivacy,
        AccountBridgeRequestNames.ReadRecentlyPlayedPrivacy,
        AccountBridgeRequestNames.SaveRecentlyPlayedPrivacy,
        AccountBridgeRequestNames.ExecutePartyRoom,
        AccountBridgeRequestNames.GetGameIdentityPolicy,
        AccountBridgeRequestNames.PrepareHandleChange,
        AccountBridgeRequestNames.ConfirmHandleChange,
        AccountBridgeRequestNames.CancelHandleChange
    };

    public static IReadOnlyList<string> AdvertisedCapabilities { get; } =
        Array.AsReadOnly([
            "overlayScenes.read",
            "overlayScenes.select",
            "overlayScenes.focusCommunity",
            "overlayScenes.focusFleet",
            "overlayScenes.fleet",
            "overlayRoster.read",
            "overlayRoster.update",
            "account.read",
            "account.offlineData.read",
            "imageCache.resources.v1",
            "account.restoreDisplay",
            "gameIdentity.prepareHandleChange",
            "gameIdentity.confirmHandleChange",
            "gameIdentity.cancelHandleChange",
            "account.avatar",
            // account.scmAvatar retired 2026-10-20: SCM users show their RSI avatar.
            "account.avatar.read",
            "account.callSign",
            "account.compatibility.read",
            "account.passwordRecovery",
        "account.legacyLogin",
        "account.redeemLegacyEntitlements",
            "account.legacySession",
            "account.compatibility.linkExisting",
            "account.lifecycle",
            "account.scmRouteRead",
            "account.scmRouteSave",
            "account.preferences.write",
            "account.profileCache.clear",
            "profile.stagedRead",
            "personalProfile.read",
            "personalProfile.write",
            "personalProfile.presentation.write.v1",
            "officialFleet.read",
            "officialFleet.deferredProfile",
            "officialFleet.ships",
            "officialFleet.shipImage",
            "officialFleet.reportShipImage",
            "officialFleet.shipImageReportStatus",
            "officialFleet.hangarSharing",
            "officialFleet.hangarSharingPage",
            "officialFleet.saveHangarSharing",
            "partyRooms.read",
            "friends.read",
            "friends.readDisplay",
            "friends.readPages",
            "friends.commandPages",
            "accountSafety.read",
            "account.supportRead",
            "account.supportClaim",
            "account.achievementIdeaSubmit",
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
            "officialFleet.communication",
            "officialFleet.communication.authorIdentities",
            "officialFleet.communication.previewAuthors",
            "officialFleet.communication.chatAuthorRenewal",
            "officialFleet.readGovernanceContext",
            "officialFleet.governanceCapabilitiesV2",
            "officialFleet.rolePolicyV2",
            "officialFleet.readRankPolicy",
            "officialFleet.writeRankPolicy",
            "officialFleet.updateRolePermissions",
            "officialFleet.readMemberRoles",
            "officialFleet.assignRole",
            "officialFleet.revokeRole",
            "officialFleet.readGovernanceAudit",
            "officialFleet.readGovernanceOutcome",
            "officialFleet.wait",
            "officialFleet.governanceRole",
            "officialFleet.readRoleTemplates",
            "officialFleet.manageRoleTemplates",
            "officialFleet.readRoleTemplateOutcome",
            "officialFleet.readAnnouncementEditor",
            "officialFleet.manageAnnouncements",
            "officialFleet.readAnnouncementOutcome",
            "officialFleet.rally",
            "officialFleet.rallyStarter",
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
            "social.wait",
            "communities.wait",
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
            "hangar.localImages",
            "hangar.localFavorites",
            "hangar.localReconciliation",
            "hangar.localPersonalData",
            "ships.specifications",
            "marketplace.read",
            "marketplace.trade",
            "marketplace.records",
            "marketplace.notices",
            "marketplace.warehouse",
            "marketplace.contracts",
            "marketplace.chat",
            "marketplace.listings",
            "tradeProfile.read",
            "tradeProfile.write",
            "marketplace.preferences",
            "personalProfile.local",
            "privacy.local",
            "eventSharing.settings",
            "friendSharing.settings",
            "gameIdVisibility.settings",
            "privacy.publication",
            "privacy.publicationEvents",
        "privacy.communityScopes",
        "privacy.locationConfidence",
        "privacy.communityMemberScopes",
            "presence.visibility",
            "presence.activity",
            "gameplayTime.local",
            "gameplayTime.history",
            "gameplayTime.historyProgress",
            "gameplayTime.reset",
            "gameLog.local",
            "achievements.read",
            "scmAchievements.read"
        ]);

    private readonly IAccountBridgeHost _host;
    private readonly Support.LocalGameEventJournal? _eventJournal;
    private readonly bool _firstUseCandidate;
    private readonly Onboarding.FirstUseOnlineCandidateIntent? _candidateIntent;
    private readonly AccountBridgeDispatcher _dispatcher;
    private readonly StarBridge.HostRuntime.Hangar.HangarReaderDispatcher _hangarReader;
    private readonly Hangar.HangarAutoSync? _hangarAutoSync;
    private bool _disposed;
    private readonly Profiles.LocalPersonalProfileDispatcher? _localProfile;
    private readonly Privacy.LocalPrivacyDispatcher? _localPrivacy;
    private readonly Privacy.PrivacyPublicationPair? _privacyPublication;
    private readonly Privacy.CommunitySharingDispatcher? _communitySharing;
    private readonly Settings.PresenceVisibilityBridge? _presenceVisibility;
    private readonly Privacy.EventSharingRuntime? _eventSharing;
    private readonly Privacy.EventSharingDispatcher? _eventSharingBridge;
    private readonly Privacy.FriendSharingRuntime? _friendSharing;
    private readonly Privacy.FriendSharingDispatcher? _friendSharingBridge;
    private readonly Privacy.GameIdSettingsDispatcher? _gameIdSettings;
    private readonly Presence.GameplayTimeRuntime? _gameplayTime;
    private Presence.GameLogRuntime? _gameLog;
    private readonly Func<Presence.GameLogRuntime>? _newDormantGameLog;
    private readonly Achievements.AchievementRuntime? _achievements;
    private AppActivityObservation? _appActivity;

    internal AccountBridgeRuntime(IAccountBridgeHost host, Hangar.LocalHangarStore? localHangar = null,
        Profiles.LocalPersonalProfileStore? localProfile = null, Presence.GameplayTimeStore? gameplayTime = null,
        Presence.GameLogSettingsStore? gameLog = null, Privacy.LocalPrivacyStore? privacy = null,
        Support.LocalGameEventJournal? eventJournal = null, Settings.PresenceVisibilityStore? visibility = null,
        string? achievementDataRoot = null, bool firstUseCandidate = false, TimeProvider? backgroundTime = null,
        Onboarding.FirstUseOnlineCandidateIntent? candidateIntent = null,
        Ships.ScmShipSpecificationReader? shipSpecifications = null)
    {
        _host = host ?? throw new ArgumentNullException(nameof(host));
        _shipSpecifications = shipSpecifications;
        _eventJournal = eventJournal;
        if (firstUseCandidate && host is not ScmAccountBridgeHost { BusinessStartupDeferred: true })
            throw new ArgumentException("A first-use candidate requires a deferred SCM owner.", nameof(host));
        if (firstUseCandidate && candidateIntent?.IsCurrent != true)
            throw new Onboarding.LocalFirstUseException("firstUse.context_changed");
        if (firstUseCandidate && candidateIntent?.Generations is { } generations)
            ((ScmAccountBridgeHost)host).BindFirstUseGenerations(generations);
        _firstUseCandidate = firstUseCandidate;
        _candidateIntent = candidateIntent;
        if (localProfile is not null) localProfile.ResolveOwner = _host.ResolveLocalDataOwner;
        _localHangarStore = localHangar;
        _dispatcher = new AccountBridgeDispatcher(host, EnabledRequests);
        if (_host is ScmAccountBridgeHost scmInbox)
        {
            scmInbox.InboxChanged += PublishInboxChanged;
            scmInbox.MarketplaceChanged += PublishMarketplaceChanged;
        }
        _hangarReader = new(() => _host.HangarIdentity, localHangar);
        try
        {
        _host.AccountChanged += InvalidateFriendsPages;
        if (localHangar is not null)
        {
            localHangar.ResolveOwner = _host.ResolveLocalDataOwner;
            _host.ConfigureHangarSharingSource(localHangar.Read);
            _host.ConfigureHangarSharingImages(localHangar.ReadCustomImage);
            _hangarAutoSync = new(_host.UpdateSharedHangarAfterSaveAsync,
                generation => _dispatcher.PublishDomainInvalidation("hangarReader.changed", generation));
            _host.AccountChanged += _hangarAutoSync.Invalidate;
        }
        if (privacy is not null)
        {
            privacy.ResolveOwner = _host.ResolveLocalDataOwner;
            if (_host is IGameIdSettingsRemote gameIdRemote)
                _gameIdSettings = new(gameIdRemote, () => _disposed ? (null, _host.Generation) : GameplayOwner());
            _localPrivacy = new(privacy, () => _disposed ? (null, _host.Generation) : GameplayOwner());
            if (_host is ScmAccountBridgeHost officialScm)
                _officialRealtimePrivacy = new(privacy, () => _disposed ? (null, _host.Generation) : GameplayOwner(),
                    officialScm.ReadOfficialRealtimeContextAsync, () => officialScm.OfficialRealtimeEnabled);
            _communitySharing = new(() => _disposed ? (null, _host.Generation) : GameplayOwner(),
                _host.ReadCommunitySharingTargetsAsync, _host.ReadCommunitySharingMembersAsync);
            _privacyPublication = new(privacy, PublicationInput, PublishCurrentPrivacyAsync,
                startTimer: !firstUseCandidate, timeProvider: backgroundTime,
                visibility: () => _presenceVisibility?.PublicationMode ?? StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Online,
                visibilitySnapshot: visibility is null ? null : () => _presenceVisibility!.ReadPublicationSnapshot(wakePublication: false),
                confirmExplicitSharing: (owner, generation) => _presenceVisibility?.ConfirmObservedModeForExplicitSharing(owner, generation),
                consumeExplicitOnlineResume: (owner, generation) => _presenceVisibility?.ConsumeExplicitOnlineResume(owner, generation) == true,
                currentOwner: PublicationOwnerInput,
                roomPublicationActive: (owner, generation) => _host is ScmAccountBridgeHost roomsScm &&
                    roomsScm.HasRoomPublication(owner, generation));
            if (_host is ScmAccountBridgeHost sharingScm)
                sharingScm.ConfigureSharedPublicationAuthorization(_privacyPublication.IsPositivePublicationAllowed,
                    _privacyPublication.IsPublicationSuspended, privacy.PositiveAdmission);
            // Status changes are pushed so the shell status light no longer polls every 5 s.
            _privacyPublication.StatusChanged += () =>
                _dispatcher.PublishDomainInvalidation("privacy.publicationChanged", _host.Generation);
            if (_host is IFriendSharingRemote friendRemote)
            {
                _friendSharing = new(friendRemote, PublicationInput, () =>
                {
                    var owner = GameplayOwner();
                    return owner.Context is not null &&
                        _privacyPublication.IsPositivePublicationAllowed(owner.Context, owner.Generation);
                }, () => _presenceVisibility?.PublicationMode ?? StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Online,
                    startTimer: !firstUseCandidate, timeProvider: backgroundTime);
                _friendSharingBridge = new(_friendSharing, () => _disposed ? (null, _host.Generation) : GameplayOwner());
            }
            if (eventJournal is not null && _host is IEventSharingRemote events && _host is IEventFeedRemote feed)
            {
                _eventSharing = new(events, feed, eventJournal, PublicationInput, () =>
                {
                    var owner = GameplayOwner();
                    return owner.Context is not null &&
                        _privacyPublication.IsPositivePublicationAllowed(owner.Context, owner.Generation);
                }, startTimer: !firstUseCandidate, timeProvider: backgroundTime);
                _eventSharingBridge = new(_eventSharing, () => _disposed ? (null, _host.Generation) : GameplayOwner());
            }
            if (visibility is not null)
            {
                Settings.PresenceVisibilityBridge CreateVisibility(Func<int?>? realtimeStatus) =>
                    new(visibility, () => _disposed ? (null, _host.Generation) : GameplayOwner(),
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
                    () => _host.PresenceRequiresSessionConfirmation,
                    realtimeStatus,
                    observeVisibility: _privacyPublication.ObserveVisibility);
                _presenceVisibility = _host is ScmAccountBridgeHost scmPresence
                    ? scmPresence.ConfigurePublicationVisibility(CreateVisibility) : CreateVisibility(null);
            }
            if (_host is ScmAccountBridgeHost scmRealtime)
            {
                scmRealtime.RealtimePresenceChanged += PublishRealtimePresence;
                scmRealtime.MarketplaceChatPushed += PublishMarketplaceChatPushed;
            }
            _host.AccountChanged += InvalidatePrivacyPublication;
        }
        if (gameLog is not null)
        {
            gameLog.ResolveOwner = _host.ResolveLocalDataOwner;
            // Reading the selected log supplies identity review; it cannot wait
            // for that same review to finish. Recording retains its own gate.
            _newDormantGameLog = () => new(gameLog, GameplayOwner, GameplayHandle, time: backgroundTime,
                startTimer: false, journal: eventJournal, recordingAllowed: () => FirstUseGameIdentityReady);
            _gameLog = _newDormantGameLog();
            _gameLog.PublicationChanged += WakeGamePublication;
            _host.AccountChanged += SuspendGameLog;
            if (!firstUseCandidate) _gameLog.StartDeferredSampling();
        }
        if (localHangar is not null && localProfile is not null)
            _localProfile = new(localProfile, localHangar, () => (_host.CurrentContext, _host.Generation));
        if (localProfile is not null && _host is ScmAccountBridgeHost scmProfile)
            scmProfile.ProfileImportCoordinator = new(localProfile, localHangar);
        if (gameplayTime is not null)
        {
            gameplayTime.ResolveOwner = _host.ResolveLocalDataOwner;
            _gameplayTime = new(gameplayTime, GameplayRecordingOwner, verifiedHandle: GameplayHandle,
                time: backgroundTime, startTimer: !firstUseCandidate,
                historyEligibility: GameplayHistoryEligibilityAsync,
                resetRemote: _host as Presence.IGameplayTimeResetRemote,
                historyRemote: _host as Presence.IGameplayHistoryRemote,
                boundLiveLog: () => _gameLog?.BoundLivePathForHistory);
            _host.AccountChanged += SuspendGameplayTime;
        }
        if (achievementDataRoot is not null && _host is Achievements.IAchievementRemote achievementRemote)
        {
            _achievementCelebration = new(GameplayOwner, achievementDataRoot);
            _host.AccountChanged += _achievementCelebration.Invalidate;
            _scmAchievementUnlocks = new(achievementDataRoot, GameplayOwner, _host.TriggerScmAchievementsAsync,
                _host.ReadScmAchievementsAsync, PublishScmAchievementEarned, backgroundTime);
            _scmAchievementUnlockStore = new(achievementDataRoot);
            _host.AccountChanged += _scmAchievementUnlocks.Invalidate;
            _achievements = new(new(achievementDataRoot), achievementRemote, GameplayOwner, () => _gameLog?.CaptureFirstEntry(),
                generation => _dispatcher.PublishDomainInvalidation("achievements.changed", generation),
                time: backgroundTime, startTimer: !firstUseCandidate,
                earned: PublishFirstEntryEarned, hangarStore: new(achievementDataRoot),
                hangarEvidence: CaptureHangarAchievementEvidence, seriesEarned: PublishSeriesEarned,
                confirmed: ObserveConfirmedAchievements, cached: ReadCachedAchievements, cityStore: new(achievementDataRoot));
            if (_gameLog is not null) _gameLog.CityArrival += ObserveCityArrival;
            _host.AccountChanged += _achievements.Invalidate;
        }
        }
        catch
        {
            // A later module can fail after earlier modules have installed
            // timers or subscriptions. The caller receives no runtime to dispose.
            // Seal admission and use the same owning-module cleanup as normal
            // disposal; this is not an asynchronous handoff/drain receipt.
            Dispose();
            throw;
        }
    }

    private void SuspendGameplayTime(long _) => _gameplayTime?.Suspend();
    private void SuspendGameLog(long _) => _gameLog?.Suspend();
    private void WakeGamePublication()
    {
        _achievements?.Observe(_gameLog?.CaptureFirstEntry());
        _liveOverlaySink?.RequestContentRefresh();
        // Leave the Game.log sampling lock before consulting account/transport
        // state. Existing publishers recheck ownership, consent and visibility.
        _ = Task.Run(async () => {
            if (FirstUseBusinessUnavailable || _disposed || _localBusinessRetired) return;
            _achievements?.Wake();
            await Task.WhenAll(_friendSharing?.TickAsync() ?? Task.CompletedTask,
                _privacyPublication?.TickAsync() ?? Task.CompletedTask);
        });
    }
    private void PublishRealtimePresence(long generation)
    {
        _dispatcher.PublishDomainInvalidation("presence.changed", generation);
        if (FirstUseBusinessUnavailable || _disposed || _localBusinessRetired || generation != _host.Generation) return;
        // Existing publishers re-evaluate consent and send withdrawals for
        // invisible/disconnected authority; this event never grants consent.
        _ = _privacyPublication?.TickAsync();
        _ = _friendSharing?.TickAsync();
        _ = _eventSharing?.TickAsync();
    }

    private void PublishMarketplaceChanged(long generation)
    {
        if (_disposed || generation != _host.Generation) return;
        _dispatcher.PublishDomainInvalidation("marketplace.changed", generation);
    }

    // Trade-chat pushes carry the message and skip the dispatch queue: delivery must not wait
    // behind an unrelated in-flight request. Flutter merges by message id, so order is free.
    private void PublishMarketplaceChatPushed(long generation, object push)
    {
        if (_disposed || generation != _host.Generation) return;
        _dispatcher.PublishLiveEvent("marketplace.chatPushed", generation, new { schemaVersion = 1, push });
    }

    private void InvalidatePrivacyPublication(long _) => _privacyPublication?.Invalidate();

    private Privacy.PrivacyPublicationInput? PublicationInput()
    {
        var input = PublicationOwnerInput();
        if (input is null) return null;
        var snapshot = _presenceVisibility?.ReadPublicationSnapshot();
        var appPresenceConfirmed = _host is ScmAccountBridgeHost && snapshot is { Observation: 1 or 2 } &&
            snapshot.Owner == input.Owner && snapshot.Generation == input.Generation;
        return input.Handle.Length == 0 && !appPresenceConfirmed ? null : input with { AppPresenceConfirmed = appPresenceConfirmed };
    }

    // Withdrawal/observation ownership is independent of a publishable Handle,
    // game identity and realtime visibility. Never sample visibility here.
    private Privacy.PrivacyPublicationInput? PublicationOwnerInput()
    {
        var owner = GameplayOwner();
        // Closed candidate lanes cannot serve account business. Its still-live
        // original SCM admission may identify the owner solely for withdrawal.
        if (owner.Context is null && _firstUseCandidate && _firstUseInstallation?.HasOriginalPublicationOwner == true)
            owner = (_host.GameplayTimeContext, _host.Generation);
        var identity = _host.HangarIdentity;
        var handle = GameplayHandle();
        if (_disposed || owner.Context is null) return null;
        handle ??= "";
        var check = _gameLog?.IdentityPolicyState ?? StarBridge.Core.Identity.LocalIdentityCheckState.NotObserved;
        var confirmed = identity is not null && check == StarBridge.Core.Identity.LocalIdentityCheckState.Match &&
            StarBridge.Core.Identity.IdentityBindingPolicy.Evaluate(identity.Identity, check).CanUseIdentitySensitiveNetworkWrites;
        // Use the same authoritative assessment as the account page for both
        // SCM and legacy sessions. A verified account need not launch the game
        // again just to share app presence; observed mismatch/revocation still
        // blocks through that assessment. Game telemetry retains its own gate.
        if (_host.ReadCurrentGameIdentityPolicy(owner.Context) is { } policy)
            confirmed = policy.SensitiveWritesAllowed;
        // All three publishers treat unconfirmed inputs as withdrawal-only.
        // Preserve owner/handle equality without restoring publication authority.
        if (_localBusinessRetired || FirstUseBusinessUnavailable) confirmed = false;
        var activity = Volatile.Read(ref _appActivity);
        return new(owner.Context, owner.Generation, handle, confirmed, ConfirmedGameVersion, CurrentGameSession,
            activity is not null && activity.Owner == owner.Context && activity.Generation == owner.Generation && activity.Away,
            AppPresenceConfirmed: false);
    }

    public async Task<bool> StopPrivacyPublicationAsync(CancellationToken token = default)
    {
        var events = _eventSharing is null || await _eventSharing.StopForShutdownAsync(token);
        var friends = _friendSharing is null || await _friendSharing.StopAsync(token, shutdown: true);
        var realtime = _privacyPublication is null || await _privacyPublication.StopAsync(token);
        return events && friends && realtime;
    }

    private Task PublishCurrentPrivacyAsync(Privacy.PrivacyPublicationInput input,
        System.Text.Json.JsonElement payload, CancellationToken token)
    {
        if (_host is not ScmAccountBridgeHost scm) return _host.PublishPrivacyAsync(input, payload, token);
        return scm.PublishPrivacyAsync(input, payload, token, () => RequireCurrentPrivacyPublication(input, payload, token));
    }

    // Shared by account admission and every writer's final callback. Kept as a
    // single method so tests exercise the same ordering as the production send.
    internal void RequireCurrentPrivacyPublication(Privacy.PrivacyPublicationInput input,
        System.Text.Json.JsonElement payload, CancellationToken token)
    {
        var withdrawal = Privacy.PrivacyRelayWriter.IsCompleteWithdrawal(payload);
        if (!withdrawal) input.RequirePositiveAdmission?.Invoke();
        var now = withdrawal ? PublicationOwnerInput() : PublicationInput();
        if (!withdrawal) _privacyPublication?.RequireNoObservedPause(input);
        if (!withdrawal && _privacyPublication?.IsPositivePublicationAllowed(input.Owner, input.Generation) != true)
            throw new OperationCanceledException("Positive publication admission has closed.", token);
        if (now is null || now.Owner != input.Owner || now.Generation != input.Generation || now.Handle != input.Handle)
            throw new AccountBridgeHostException("privacy_publication.account_changed");
        // Lifecycle closure cancels positive work, not durable sharing
        // consent. A compensating clear still belongs to this same owner.
        if (!withdrawal && (_localBusinessRetired || FirstUseBusinessUnavailable ||
            !(now.IdentityConfirmed || Privacy.PrivacyPublicationPayload.IsOfficialAppOnly(payload) && now.AppPresenceConfirmed)))
            throw new OperationCanceledException("Positive publication admission has closed.", token);
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
        if (FirstUseBusinessUnavailable || _disposed) return (null, generation);
        var context = _host.GameplayTimeContext;
        return (generation == _host.Generation ? context : null, generation);
    }

    public long Generation => _host.Generation;
    public StarBridge.Core.Presence.PlayerPresenceVisibilityMode AppStatsPresenceVisibilityMode => _disposed
        ? StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Offline
        : _presenceVisibility?.PublicationMode ?? StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Online;
    public Uri? DiagnosticsRelayUri { get; private set; }
    public Overlay.IInstalledAppearanceProgress? CreateInstalledAppearanceProgress()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        Overlay.IInstalledAppearanceProgress? progress = null;
        CreateInstalledAppearanceProgressCore(ref progress);
        return progress;
    }
    partial void CreateInstalledAppearanceProgressCore(ref Overlay.IInstalledAppearanceProgress? progress);
    public string? ConfirmedGameVersion => _gameLog?.ConfirmedVersion;
    public string? SelectedGameLogPathForDiagnostics => _gameLog?.SelectedPathForDiagnostics;
    public Presence.GameLogSessionSnapshot CurrentGameSession =>
        _gameLog?.CurrentSession ?? Presence.GameLogSessionSnapshot.Empty;
    public IReadOnlyList<string> CurrentOverlayEntitlements =>
        ReadCurrentOverlayEntitlements();

    public Overlay.InformationOverlayRoomContent? CurrentRoomOverlay => _host.CurrentRoomOverlay;

    public static AccountBridgeRuntime CreateIsolatedSandboxShell() =>
        new(new EnvironmentLockedAccountBridgeHost("hangar-sandbox"));

    public event Action<BridgeEnvelope>? EventReady
    {
        add => _dispatcher.EventReady += value;
        remove => _dispatcher.EventReady -= value;
    }

    public static Task<AccountBridgeRuntime> CreateDefaultAsync(
        Func<string?>? detectedGameIdentity = null,
        CancellationToken cancellationToken = default,
        Support.LocalGameEventJournal? eventJournal = null, bool enableFirstUseModes = true)
    {
        var root = HostDataRoot.CurrentRoot;
        return CreateWithFirstUseModeAsync(root,
            token => CreateOnlineDefaultAsync(root, false, detectedGameIdentity, token, eventJournal), cancellationToken,
            eventJournal: eventJournal, enableFirstUseModes: enableFirstUseModes);
    }

    private static async Task<AccountBridgeRuntime> CreateOnlineDefaultAsync(string dataRoot, bool requireFreshSignIn,
        Func<string?>? detectedGameIdentity, CancellationToken cancellationToken,
        Support.LocalGameEventJournal? eventJournal, Onboarding.FirstUseOnlineCandidateIntent? candidateIntent = null)
    {
        var firstUseCandidate = candidateIntent is not null;
        if ((requireFreshSignIn || firstUseCandidate) && candidateIntent?.IsCurrent != true ||
            firstUseCandidate && requireFreshSignIn == candidateIntent!.RetainSession)
            throw new Onboarding.LocalFirstUseException("firstUse.context_changed");
        var configuration = await ScmRuntimeConfiguration.ResolveDefaultAsync(
                dataRoot,
                cancellationToken)
            .ConfigureAwait(false);
        if (!configuration.AccountAccessEnabled)
        {
            if (firstUseCandidate) throw new Onboarding.LocalFirstUseException("firstUse.online_unavailable");
            return new AccountBridgeRuntime(
                new EnvironmentLockedAccountBridgeHost(configuration.EnvironmentId)) { RouteState = configuration.RouteState };
        }

        var http = new ScmHttpClient();
        var deviceId = ScmDeviceId.LoadOrCreate(dataRoot);
        var oauth = new OAuthPkceClient(
            http,
            new WindowsTokenVault(configuration.TokenVaultPath),
            configuration.OAuthOptions,
            () => deviceId) { RouteState = configuration.RouteState };
        AccountBridgeRuntime? runtime = null;
        ScmAccountBridgeHost? createdHost = null;
        AccountBridgeRuntime ConstructRuntime() => CreateAccountBusinessRuntime(
            createdHost = new ScmAccountBridgeHost(
                oauth,
                new ScmProfileCacheStore(dataRoot),
                configuration.EnvironmentId,
                detectedGameIdentity ?? (() => runtime?._gameLog?.DetectedHandle),
                recentGameIdentity: detectedGameIdentity is null ? () => runtime?._gameLog?.RecentDetectedHandle : null,
                lastGameIdentityCheck: detectedGameIdentity is null
                    ? () => runtime?._gameLog?.IdentityPolicyState ??
                            StarBridge.Core.Identity.LocalIdentityCheckState.NotObserved
                    : null,
                partyRooms: new PartyRooms.PartyRoomReader(configuration.LegacyRelayBaseUri),
                // Realtime v1 is attempted against the relay; an older relay or the
                // gateway switch off answers 404 and the HTTP long polls continue.
                friends: new Friends.FriendsReader(configuration.LegacyRelayBaseUri, realtime: true) {
                    RealtimeDiagnostic = new Realtime.RealtimeGatewayJournal(dataRoot).Record
                },
                accountSafety: new AccountSafetyClient(configuration.LegacyRelayBaseUri),
                dailySupport: new DailySupportClient(configuration.LegacyRelayBaseUri),
                achievementIdeas: new AchievementIdeaClient(configuration.LegacyRelayBaseUri),
                communities: new Communities.CommunityClient(configuration.LegacyRelayBaseUri) {
                    ReadDiagnostic = new Privacy.CommunityReadJournal(dataRoot).Record,
                    ChatAuthorDiagnostic = new Privacy.OfficialChatAuthorReadJournal(dataRoot).Record
                },
                hangarMedia: new Hangar.HangarMediaClient(configuration.LegacyRelayBaseUri),
                compatibilityReader: S2CompatibilityReader.Create(http, oauth, configuration),
                passwordRecovery: new LegacyPasswordRecoveryClient(configuration.LegacyRelayBaseUri),
                legacyPasswordLogin: new LegacyPasswordLoginClient(configuration.LegacyRelayBaseUri,
                    new WindowsLegacyMigrationCredentialStore(configuration.LegacyMigrationCredentialPath),
                    sessionStore: new WindowsLegacyMigrationCredentialStore(
                        configuration.LegacyMigrationCredentialPath + ".active-" +
                        Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
                            System.Text.Encoding.UTF8.GetBytes(configuration.LegacyRelayBaseUri.AbsoluteUri)))[..16] + ".dat")),
                requireFreshSignIn: requireFreshSignIn, deferBusinessStartup: firstUseCandidate,
                requireRetainedFirstUseSession: candidateIntent?.RetainSession == true),
            dataRoot, eventJournal, firstUseCandidate, candidateIntent);
        try
        {
            runtime = ConstructRuntime();
            runtime.RouteState = configuration.RouteState;
            runtime._shipSpecifications = new(configuration.OAuthOptions.AuthorizationServerBaseUri);
            runtime._marketplace = new(configuration.OAuthOptions.AuthorizationServerBaseUri);
            runtime._marketplacePreferences = new(dataRoot);
        }
        catch { createdHost?.Dispose(); throw; }
        if (firstUseCandidate) runtime.InitializeOfflineAccount(dataRoot);
        if (runtime._host is ScmAccountBridgeHost scm)
        {
            var privacyWriter = new Privacy.PrivacyRelayWriter(configuration.LegacyRelayBaseUri);
            var publicationJournal = new Privacy.CommunityReadJournal(dataRoot);
            scm.OfficialFleetDiagnostic = publicationJournal.Record;
            privacyWriter.PublicationDiagnostic = publicationJournal.Record;
            privacyWriter.ReceiptDiagnostic = publicationJournal.RecordReceipt;
            // [DEBUG-community-read] Opt in only for the local integration Relay.
            if (configuration.LegacyRelayBaseUri.IsLoopback)
            {
                var journal = new Privacy.CommunityReadJournal(dataRoot);
                privacyWriter.CommunityReadDiagnostic = journal.Record;
                scm.PrivacyPublicationDiagnostic = journal.Record;
                if (runtime._communitySharing is { } communitySharing)
                    communitySharing.Diagnostic = journal.Record;
            }
            scm.ConfigurePrivacyWriter(privacyWriter);
            scm.ConfigureOfficialRealtime(OfficialRealtimeEnabledByConfiguration(
                Environment.GetEnvironmentVariable("STARBRIDGE_OFFICIAL_FLEET_REALTIME_ENABLED")));
            scm.EnableRoomMembershipKeepalive();
            scm.EnableParticipantSynchronization();
        }
        if (runtime._friendSharing is { } sharing)
            sharing.Diagnostic = new Privacy.FriendSharingJournal(dataRoot).Record;
        if (runtime._privacyPublication is { } realtime)
            realtime.Diagnostic = new Privacy.PrivacyPublicationJournal(dataRoot).Record;
        runtime.DiagnosticsRelayUri = configuration.LegacyRelayBaseUri;
        if (firstUseCandidate && candidateIntent?.IsCurrent != true)
        {
            runtime.Dispose();
            throw new Onboarding.LocalFirstUseException("firstUse.context_changed");
        }
        return runtime;
    }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (_firstUseCandidate && _candidateIntent?.IsCurrent != true)
            return new(BridgeEnvelope.ErrorResponse(request,
                new BridgeError("firstUse.context_changed", "Account setup has changed. Return to setup and try again.")), []);
        if (_firstUseCandidate && request.Name is not (AccountBridgeRequestNames.GetCurrent or
            AccountBridgeRequestNames.Login or AccountBridgeRequestNames.CancelLogin or AccountBridgeRequestNames.Logout))
            return new(BridgeEnvelope.ErrorResponse(request,
                new BridgeError("firstUse.candidate_not_attached", "Online features are not available during account setup. Return to setup to continue.")), []);
        if (RetainsFirstUseSession && request.Name != AccountBridgeRequestNames.GetCurrent)
            return new(BridgeEnvelope.ErrorResponse(request,
                new BridgeError("firstUse.resume_required", "Return to setup to resume the retained session.")), []);
        if (Images.RemoteImageCacheBridge.Requests.Contains(request.Name))
            return await DispatchImageCacheAsync(request, cancellationToken).ConfigureAwait(false);
        Lifecycle.AsyncWorkRetirement.Lease? lease;
        try { lease = _requestRetirement.Enter(cancellationToken); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        if (lease is null)
            return new(BridgeEnvelope.ErrorResponse(request,
                new BridgeError("account.local_mode", "Online account work is paused.")), []);
        using (lease)
        {
            using var restoreDisplay = EnterRestoreDisplay(request, lease.Token);
            using var friendsDisplay = EnterFriendsDisplay(request, lease.Token);
            try
            {
                BridgeDispatchBatch result;
                try { result = await DispatchCoreAsync(request, lease.Token).ConfigureAwait(false); }
                finally
                {
                    // Retire old/in-flight directories after the mutation, then
                    // create this confirmed result's pages at the new revision.
                    if (request.Name == AccountBridgeRequestNames.ExecuteFriend) RetireFriendsPages();
                }
                try
                {
                    result = new(PrepareFriendsPageResponse(request, result.Response, friendsDisplay), result.Events);
                    if (!_firstUseCandidate) ObserveOfflineAccount(request, result.Response, () => lease.IsCurrent && !_disposed &&
                        result.Response.AccountContext == _host.CurrentContext && request.SessionGeneration == Generation);
                    if (!_firstUseCandidate)
                        result = new(AddRetainedAccountDisplay(request, result.Response,
                            () => lease.IsCurrent && !_disposed && request.SessionGeneration == Generation), result.Events);
                    if (!_firstUseCandidate)
                        result = new(AddSignedInCachedAvatar(request, result.Response,
                            () => lease.IsCurrent && !_disposed), result.Events);
                    result = new(CompleteRestoreDisplay(restoreDisplay, result.Response), result.Events);
                }
                catch (Exception failure) when (failure is not (OperationCanceledException or BridgeProtocolException))
                {
                    // Only the response decoration failed. The request's account transition
                    // already happened, so its events must still reach the client.
                    result = new(NativeHostPipeServer.UnexpectedFailure(request, failure), result.Events);
                }
                if (lease.IsCurrent && (!_firstUseCandidate || _candidateIntent?.IsCurrent == true)) return result;
                // Caller cancellation retires this response, not an independent
                // real account transition collected during its IO. Never revive
                // domain events or an exited/retired installation graph.
                var rootEvents = !_disposed && !_firstUseCandidate && !_requestRetirement.IsClosed
                    ? result.Events.Where(e => e.Name == "account.changed" && e.SessionGeneration == Generation).ToArray()
                    : [];
                return new(BridgeEnvelope.CancelledResponse(request), rootEvents);
            }
            catch (OperationCanceledException) when (!lease.IsCurrent)
            { return new(BridgeEnvelope.CancelledResponse(request), []); }
        }
    }

    private async ValueTask<BridgeDispatchBatch> DispatchCoreAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken)
    {
        if (request.Name is "account.scmRouteRead" or "account.scmRouteSave")
            return DispatchScmRoute(request, cancellationToken);
        if (Images.RemoteImageCacheBridge.Requests.Contains(request.Name))
            return await DispatchImageCacheAsync(request, cancellationToken).ConfigureAwait(false);
        if (request.Name == "scmAchievements.read") return await ReadScmAchievementsAsync(request, cancellationToken);
        if (request.Name == AccountBridgeRequestNames.ReadFriendsPage) return ReadFriendsPage(request, cancellationToken);
        if (request.Name == AccountBridgeRequestNames.ExecuteFriend) RetireFriendsPages();
        if (request.Name == RetainedDataRequest) return ReadRetainedData(request, cancellationToken);
        if (_officialRealtimePrivacy is not null && request.Name is "privacy.officialFleetRead" or "privacy.officialFleetSave")
            return await _officialRealtimePrivacy.DispatchAsync(request, cancellationToken);
        if (_achievementIdeaImages is not null && request.Name == "achievementIdeas.pickImage")
            return await _achievementIdeaImages.DispatchAsync(request, cancellationToken);
        if (_eventSharingBridge is not null && request.Name is "eventSharing.read" or "eventSharing.save")
            return await _eventSharingBridge.DispatchAsync(request, cancellationToken);
        if (_friendSharingBridge is not null && request.Name is "friendSharing.read" or "friendSharing.save")
            return await _friendSharingBridge.DispatchAsync(request, cancellationToken);
        if (_gameIdSettings is not null && request.Name is "gameIdVisibility.read" or "gameIdVisibility.save")
            return await _gameIdSettings.DispatchAsync(request, cancellationToken);
        if (_overlayCommunities is not null && request.Name is "overlayRoster.read" or "overlayRoster.update")
            return await _overlayCommunities.DispatchRosterAsync(request, cancellationToken);
        if (_overlayCommunities is not null && request.Name is "overlayScenes.read" or "overlayScenes.select" or "overlayScenes.focusCommunity" or "overlayScenes.focusFleet")
            return await _overlayCommunities.DispatchAsync(request, cancellationToken).ConfigureAwait(false);
        if (_communityLogo is not null && Communities.CommunityLogoBridge.Requests.Contains(request.Name))
            return await _communityLogo.DispatchAsync(request, cancellationToken).ConfigureAwait(false);
        if (_hangarImages is not null && Hangar.HangarImageDraftBridge.Requests.Contains(request.Name))
        {
            var imageResult = await _hangarImages.DispatchAsync(request, cancellationToken).ConfigureAwait(false);
            if (request.Name is "hangarImage.save" or "hangarImage.restore" && imageResult.Response.Status == BridgeResponseStatuses.Ok)
                _dispatcher.PublishDomainInvalidation("hangarReader.changed", request.SessionGeneration);
            return imageResult;
        }
        if (_communitySharing is not null && request.Name is "privacy.communityTargets" or "privacy.communityMembers")
            return await _communitySharing.DispatchAsync(request, cancellationToken).ConfigureAwait(false);
        if (_presenceVisibility is not null && request.Name is "presence.read" or "presence.set")
        {
            var batch = await _presenceVisibility.DispatchAsync(request, cancellationToken).ConfigureAwait(false);
            if (request.Name == "presence.set" && batch.Response.Status == BridgeResponseStatuses.Ok &&
                batch.Response.Payload.TryGetProperty("state", out var state) && state.GetString() == "ready")
                // The confirmed mode is already durable and publication pause
                // released. Wake the existing serialized publisher; do not hold
                // the settings response behind another network acknowledgement.
                _ = _friendSharing?.TickAsync();
            return batch;
        }
        if (request.Name == "presence.activity")
            return DispatchAppActivity(request);
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
                        !(request.Name == "privacy.applyPublication" && p.Name is "expectedRevision" or "preservePause")))
                    throw new Privacy.LocalPrivacyException("privacy_publication.invalid_request");
                if (request.Name == "privacy.applyPublication")
                    await _privacyPublication.ApplyAsync(owner.Context, owner.Generation,
                        request.Payload.GetProperty("expectedRevision").GetInt64(), cancellationToken,
                        request.Payload.TryGetProperty("preservePause", out var preservePause) && preservePause.GetBoolean()).ConfigureAwait(false);
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
            catch (TimeoutException)
            { return new(BridgeEnvelope.ErrorResponse(request, new("privacy_publication.timeout", "Privacy publication temporarily unavailable.", true)), []); }
            catch (OperationCanceledException)
            { return new(BridgeEnvelope.CancelledResponse(request), []); }
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
        if (request.Name.StartsWith("achievements.", StringComparison.Ordinal))
            return _achievements is not null ? await _achievements.DispatchAsync(request, cancellationToken).ConfigureAwait(false) :
                new(BridgeEnvelope.ErrorResponse(request, new("achievements.unavailable", "Cloud achievement collection is unavailable.", true)), []);
        if (request.Name == "ships.specifications")
            return await ReadShipSpecificationsAsync(request, cancellationToken).ConfigureAwait(false);
        if (request.Name is "marketplace.read" or "marketplace.preferences" or "marketplace.trade" or "marketplace.records" or "marketplace.contracts" or "marketplace.warehouse" or "marketplace.notices" or "marketplace.chat" or "marketplace.listings" or "tradeProfile.read" or "tradeProfile.write")
            return await DispatchMarketplaceAsync(request, cancellationToken).ConfigureAwait(false);
        if (request.Name.StartsWith("hangarReader.", StringComparison.Ordinal))
        {
            var batch = _hangarReader.Dispatch(request, cancellationToken);
            if (request.Name is "hangarReader.favorite" or "hangarReader.personalData" && batch.Response.Status == BridgeResponseStatuses.Ok)
                return new(batch.Response, [_dispatcher.DomainInvalidation("hangarReader.changed", request.SessionGeneration)]);
            if (request.Name == "hangarReader.save" && batch.Response.Status == BridgeResponseStatuses.Ok)
            {
                // A committed local import remains successful if its separate
                // organization publication is unavailable. Never roll it back.
                if (batch.Response.Payload.TryGetProperty("partial", out var partial) && !partial.GetBoolean())
                {
                    _achievements?.Wake();
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
            {
                // Save released positive admission before waiting for _gate.
                // A close waits for the admitted send, commits revocation, then
                // immediately clears; a failed clear remains a retry obligation.
                if (batch.Response.Payload.GetProperty("settings").GetProperty("publicationEnabled").ValueKind == System.Text.Json.JsonValueKind.False)
                    await _privacyPublication.StopAsync(cancellationToken, explicitRequest: true).ConfigureAwait(false);
                else _ = _privacyPublication.TickAsync();
            }
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
        if (request.Name != "bridge.cancel" && !EnabledRequests.Contains(request.Name))
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
        if (request.Name == AccountBridgeRequestNames.Logout && result.Response.Status == BridgeResponseStatuses.Ok &&
            request.AccountContext is { } signedOutOwner && _host.CurrentContext is null)
        {
            try { _offlineAccount?.ClearAchievements(signedOutOwner, () => !_disposed && _host.CurrentContext is null); }
            catch (Exception error) when (CacheFailure(error)) { }
            try { _offlineAccount?.ClearFriends(signedOutOwner, () => !_disposed && _host.CurrentContext is null); }
            catch (Exception error) when (CacheFailure(error)) { }
        }
        return new BridgeDispatchBatch(result.Response, result.Events);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _host.AccountChanged -= InvalidateFriendsPages;
        _friendPages.Clear();
        if (_host is ScmAccountBridgeHost offlineSource)
        {
            offlineSource.AuthenticatedSessionRetired -= RetireOfflineAppearanceProof;
            offlineSource.AccountDisplayObserved -= ObserveAccountDisplay;
            offlineSource.FriendsReadStarting -= BeginFriendsDisplayRead;
            offlineSource.FriendsReadFinished -= CompleteFriendsDisplayRead;
        }
        _ = _ordinaryDeviceNetwork?.RetireAsync();
        _ = _firstUseInstallation?.SealAndDrainAsync();
        CloseFirstUseMode();
        _ = _backgroundConfiguration.Close();
        _ = _requestRetirement.Close();
        DisposeImageCache();
        _ = _firstUseBusinessPreparation.Close();
        _host.AccountChanged -= InvalidateMenuHotkeys;
        _menuHotkeys?.Invalidate();
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
        if (_ownsPlayerActivity) _playerActivity?.Dispose();
        else _playerActivity?.Reset();
        _host.AccountChanged -= InvalidateGameplayExport;
        _gameplayExport?.Dispose();
        _host.AccountChanged -= InvalidateCommunityLogo;
        _communityLogo?.Dispose();
        _host.AccountChanged -= InvalidateHangarImages;
        _hangarImages?.Dispose();
        _host.AccountChanged -= InvalidateAchievementIdeaImages;
        _achievementIdeaImages?.Dispose();
        _host.AccountChanged -= InvalidatePrivacyPublication;
        if (_host is ScmAccountBridgeHost scmRealtime)
        {
            scmRealtime.RealtimePresenceChanged -= PublishRealtimePresence;
            scmRealtime.MarketplaceChanged -= PublishMarketplaceChanged;
            scmRealtime.InboxChanged -= PublishInboxChanged;
            scmRealtime.MarketplaceChatPushed -= PublishMarketplaceChatPushed;
        }
        DisposeTradeNotifications();
        _privacyPublication?.Dispose();
        _presenceVisibility?.Dispose();
        _eventSharing?.Dispose();
        _friendSharing?.Dispose();
        _activityReceiver?.Dispose();
        DisposeLiveOverlayUpdates();
        _host.AccountChanged -= SuspendGameplayTime;
        _host.AccountChanged -= SuspendGameLog;
        if (_achievements is not null) _host.AccountChanged -= _achievements.Invalidate;
        _achievements?.Dispose();
        if (_achievementCelebration is not null) _host.AccountChanged -= _achievementCelebration.Invalidate;
        _achievementCelebration?.Dispose();
        if (_scmAchievementUnlocks is not null) _host.AccountChanged -= _scmAchievementUnlocks.Invalidate;
        _scmAchievementUnlocks?.Dispose();
        if (_gameLog is not null) _gameLog.CityArrival -= ObserveCityArrival;
        if (_gameLog is not null) _gameLog.PublicationChanged -= WakeGamePublication;
        _gameLog?.Dispose();
        _gameplayTime?.Dispose();
        _dispatcher.Dispose();
        _hangarReader.Dispose();
        _shipSpecifications?.Dispose();
        _marketplace?.Dispose();
        if (_host is IDisposable disposableHost)
        {
            disposableHost.Dispose();
        }
    }
}

