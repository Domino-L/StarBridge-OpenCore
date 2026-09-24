namespace StarBridge.HostRuntime.Account;

using StarBridge.Core.Profiles;
using StarBridge.NativeBridge;

internal static class AccountBridgeSchema
{
    internal const int Version = 1;
}

internal static class AccountBridgeRequestNames
{
    internal const string GetCurrent = "account.getCurrent";
    internal const string UpdateAvatar = "account.updateAvatar";
    internal const string Login = "account.login";
    internal const string CancelLogin = "account.cancelLogin";
    internal const string Logout = "account.logout";
    internal const string GetProfile = "profile.getSelf";
    internal const string GetPersonalProfile = "personalProfile.getSelf";
    internal const string ReadMigrationHangar = "hangar.migrationRead";
    internal const string UpdatePersonalProfile = "personalProfile.updateSelf";
    internal const string GetLegacyProfileMigrationStatus = "personalProfile.migrationStatus";
    internal const string PreviewLegacyProfileMigration = "personalProfile.migrationPreview";
    internal const string ConfirmLegacyProfileMigration = "personalProfile.migrationConfirm";
    internal const string GetOfficialFleet = "officialFleet.getCurrent";
    internal const string GetPartyRooms = "partyRooms.getDirectory";
    internal const string ReadFriends = "friends.read";
    internal const string ReadAccountSafety = "accountSafety.read";
    internal const string ReadNotificationInbox = "notificationInbox.read";
    internal const string MarkNotificationInboxRead = "notificationInbox.markRead";
    internal const string SubmitAccountAppeal = "accountSafety.appeal";
    internal const string ReadCommunities = "communities.read";
    internal const string ExecuteCommunity = "communities.execute";
    internal const string GetCommunityCreationOptions = "communities.creationOptions";
    internal const string CreateCommunity = "communities.create";
    internal const string ReadCommunityWorkspace = "communities.workspace";
    internal const string ReadCommunityLogs = "communities.logs";
    internal const string DeleteCommunityLog = "communities.deleteLog";
    internal const string ReadCommunityDisband = "communities.disbandPreview";
    internal const string ReadCommunityChat = "communities.chat";
    internal const string ReadCommunityAnnouncements = "communities.announcements";
    internal const string ReadCommunityShips = "communities.ships";
    internal const string ReadCommunityHangarSharing = "communities.hangarSharing";
    internal const string SaveCommunityHangarSharing = "communities.saveHangarSharing";
    internal const string ReadCommunityShipImage = "communities.shipImage";
    internal const string ReportCommunityShipImage = "communities.reportShipImage";
    internal const string ReadCommunityAnnouncementDetail = "communities.announcementDetail";
    internal const string ManageCommunityAnnouncements = "communities.manageAnnouncements";
    internal const string ReadCommunityChatDetail = "communities.chatDetail";
    internal const string MarkCommunityChatRead = "communities.markChatRead";
    internal const string SendCommunityChat = "communities.sendChat";
    internal const string DisbandCommunity = "communities.disband";
    internal const string ReadCommunityMedia = "communities.media";
    internal const string ReadCommunityProfile = "communities.profile";
    internal const string ReadCommunityAdmissions = "communities.admissions";
    internal const string ManageCommunityAdmissions = "communities.manageAdmissions";
    internal const string SaveCommunityProfile = "communities.saveProfile";
    internal const string ReadCommunityRoles = "communities.roles";
    internal const string SaveCommunityRoles = "communities.saveRoles";
    internal const string ReadCommunityMemberRole = "communities.memberRole";
    internal const string SaveCommunityMemberRole = "communities.saveMemberRole";
    internal const string ReadCommunityMemberRemoval = "communities.memberRemoval";
    internal const string RemoveCommunityMember = "communities.removeMember";
    internal const string ReadCommunityOwnershipTransfer = "communities.ownershipTransfer";
    internal const string TransferCommunityOwnership = "communities.transferOwnership";
    internal const string ReadCommunityOwnershipExit = "communities.ownershipExit";
    internal const string LeaveCommunityWithSuccessor = "communities.leaveWithSuccessor";
    internal const string PreviewCommunityInvite = "communities.previewInvite";
    internal const string AcceptCommunityInvite = "communities.acceptInvite";
    internal const string SendCommunityInvite = "communities.sendInvite";
    internal const string ResumeCommunityInvite = "communities.resumeInvite";
    internal const string ReadCommunityInvitationOutbox = "communities.invitationOutbox";
    internal const string ExecuteFriend = "friends.execute";
    internal const string ReadDirectMessages = "directMessages.read";
    internal const string SendDirectMessage = "directMessages.send";
    internal const string MarkDirectMessagesRead = "directMessages.markRead";
    internal const string ReadDirectMessagePrivacy = "directMessages.privacyRead";
    internal const string SaveDirectMessagePrivacy = "directMessages.privacyWrite";
    internal const string ReadFriendRequestPrivacy = "friendRequests.privacyRead";
    internal const string SaveFriendRequestPrivacy = "friendRequests.privacyWrite";
    internal const string ReadRecentlyPlayedPrivacy = "recentlyPlayed.privacyRead";
    internal const string SaveRecentlyPlayedPrivacy = "recentlyPlayed.privacyWrite";
    internal const string ExecutePartyRoom = "partyRooms.execute";
    internal const string GetCompatibilityState = "account.getCompatibilityState";
    internal const string SendPasswordResetCode = "account.sendPasswordResetCode";
    internal const string LoginLegacy = "account.loginLegacy";
    internal const string RedeemLegacyEntitlements = "account.redeemLegacyEntitlements";
    internal const string ConfirmPasswordReset = "account.confirmPasswordReset";
    internal const string LinkLegacyAccount = "account.linkLegacyAccount";
    internal const string CreateCompatibilityIdentity = "account.createCompatibilityIdentity";
    internal const string PatchPreferences = "profile.patchPreferences";
    internal const string ClearProfileCache = "profile.clearLocalCache";
    internal const string GetGameIdentityPolicy = "gameIdentity.getPolicy";
}

internal static class AccountBridgeStableErrors
{
    internal const string EnvironmentNotEnabled = "account.environment_not_enabled";
    internal const string LoginCancelled = "account.login_cancelled";
    internal const string LoginTimeout = "account.login_timeout";
    internal const string ReauthorizationRequired = "account.reauthorization_required";
    internal const string OperationInProgress = "account.operation_in_progress";
    internal const string ProfileReadUnavailable = "profile.read_unavailable";
    internal const string ProfileWriteForbidden = "profile.write_forbidden";
    internal const string ProfileWriteConflict = "profile.write_conflict";
    internal const string ProfileDirectoryUnavailable = "profile.directory_unavailable";
    internal const string GameIdentityReadUnavailable = "game_identity.read_unavailable";
    internal const string CompatibilityReadUnavailable = "account.compatibility_read_unavailable";
    internal const string CompatibilityWriteUnavailable = "account.compatibility_write_unavailable";
    internal const string CompatibilityConflict = "account.compatibility_conflict";
    internal const string CompatibilityExistingLinkMismatch = "account.compatibility_existing_link_mismatch";
    internal const string LegacyCredentialsRequired = "account.legacy_credentials_required";
    internal const string LegacyCredentialsRejected = "account.legacy_credentials_rejected";
    internal const string PersonalProfileReadUnavailable = "personal_profile.read_unavailable";
    internal const string PersonalProfileWriteForbidden = "personal_profile.write_forbidden";
    internal const string PersonalProfileWriteConflict = "personal_profile.write_conflict";
    internal const string OfficialFleetReadUnavailable = "official_fleet.read_unavailable";
    internal const string OfficialFleetDataInvalid = "official_fleet.data_invalid";
}

internal sealed record AccountBridgeSessionProjection(
    string State,
    long Generation,
    BridgeAccountContext? Context,
    string? DisplayName,
    string? AvatarUrl,
    string? AvatarImageData = null,
    string? MaskedAccount = null);

internal sealed record AccountBridgeProfile(
    string? DisplayName,
    string? AvatarUrl,
    string? Email,
    string? Locale,
    string? TimeZone);

internal sealed record AccountBridgeTimeZone(
    string Value,
    string Label,
    string Offset);

internal sealed record AccountBridgeProfileProjection(
    AccountBridgeProfile Profile,
    string Source,
    DateTimeOffset? CachedAtUtc,
    IReadOnlyList<string> Locales,
    IReadOnlyList<AccountBridgeTimeZone> TimeZones);

internal readonly record struct AccountBridgePatchField(
    bool IsSpecified,
    string? Value)
{
    internal static AccountBridgePatchField Unspecified => new(false, null);
    internal static AccountBridgePatchField Set(string? value) => new(true, value);
}

internal sealed record AccountBridgePreferencePatch(
    AccountBridgePatchField Locale,
    AccountBridgePatchField TimeZone)
{
    internal bool IsEmpty => !Locale.IsSpecified && !TimeZone.IsSpecified;
}

internal sealed record AccountBridgeIdentityProjection(
    string State,
    string? AuthoritativeHandle,
    bool SensitiveWritesAllowed);

internal sealed record AccountBridgeCompatibilityProjection(
    string IdentityState,
    string RelayState,
    bool StoredLegacyCredentialAvailable,
    bool LegacyFeaturesAvailable,
    IReadOnlyList<string> AvailableActions,
    string? LegacyAccountId);

internal sealed record AccountBridgeOfficialFleetSummary(
    string SourceRef,
    string Sid,
    string Name,
    string? LogoUrl,
    string? OfficialRankName,
    int? OfficialRankValue);

internal sealed record AccountBridgeOfficialFleetProjection(
    string State,
    AccountBridgeOfficialFleetSummary? Fleet,
    string Freshness,
    long? ResourceVersion,
    DateTimeOffset ObservedAtUtc);

internal sealed record AccountBridgeLegacyCredential(
    string AccountName,
    string Password);

internal interface IAccountBridgeHost
{
    Task<object> UpdateAvatarAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("account.avatar_unavailable"));
    bool PresenceRequiresSessionConfirmation => true;
    Task<StarBridge.Core.Presence.PlayerPresenceVisibilityMode> SetPresenceVisibilityAuthorityAsync(
        BridgeAccountContext owner, long generation, StarBridge.Core.Presence.PlayerPresenceVisibilityMode mode,
        CancellationToken token) => Task.FromException<StarBridge.Core.Presence.PlayerPresenceVisibilityMode>(
            new AccountBridgeHostException("presence.unavailable"));

    Task PublishPrivacyAsync(StarBridge.HostRuntime.Privacy.PrivacyPublicationInput input,
        System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException(new AccountBridgeHostException("privacy_publication.unavailable"));

    Task<StarBridge.HostRuntime.Privacy.CommunitySharingTargets> ReadCommunitySharingTargetsAsync(
        BridgeAccountContext owner, long generation, CancellationToken token) =>
        Task.FromException<StarBridge.HostRuntime.Privacy.CommunitySharingTargets>(
            new AccountBridgeHostException("privacy_publication.community_scopes_unavailable"));

    Task<StarBridge.Core.Presence.CommunityMemberDirectoryPage> ReadCommunitySharingMembersAsync(
        BridgeAccountContext owner, long generation, StarBridge.Core.Presence.CommunityMemberDirectoryRequest input,
        CancellationToken token) => Task.FromException<StarBridge.Core.Presence.CommunityMemberDirectoryPage>(
            new AccountBridgeHostException("privacy_publication.member_scopes_unavailable"));

    StarBridge.HostRuntime.Hangar.HangarAccountIdentity? HangarIdentity => null;

    long Generation { get; }

    BridgeAccountContext? CurrentContext { get; }

    // Opt-in only after the active session transport is audited for overlapping
    // reads. Authentication/restoration and all writes remain exclusive.
    bool SupportsConcurrentReads => false;

    IReadOnlyList<string> CurrentOverlayEntitlements => [];

    StarBridge.HostRuntime.Overlay.InformationOverlayRoomContent? CurrentRoomOverlay => null;

    BridgeAccountContext? GameplayTimeContext => CurrentContext;

    event Action<long>? AccountChanged;

    Task<AccountBridgeSessionProjection> GetCurrentAsync(CancellationToken cancellationToken);

    Task<AccountBridgeSessionProjection> LoginAsync(CancellationToken cancellationToken);

    Task CancelLoginAsync();

    Task LogoutAsync(BridgeAccountContext context, CancellationToken cancellationToken);

    Task<AccountBridgeProfileProjection> GetProfileAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken);

    Task<PersonalProfileDocumentContract> GetPersonalProfileAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken);

    Task<object> ProfileVisibilityAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload,
        bool save, CancellationToken token) => throw new AccountBridgeHostException("profile.visibility_unavailable");

    Task<PersonalProfileDocumentContract> ReadMemberPersonalProfileAsync(BridgeAccountContext context,
        System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("profile.visitor_unavailable");

    Task<PersonalProfileDocumentContract> ReadUserProfileAsync(BridgeAccountContext context,
        System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("profile.visitor_unavailable");
    Task<StarBridge.HostRuntime.Friends.FriendsView> ReadUserSocialAsync(BridgeAccountContext context,
        System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("friends.read_unavailable");

    Task<object> ReadMigrationHangarAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("hangar.migration_source_unavailable");

    Task<StarBridge.HostRuntime.Auth.LegacyProfileMigrationView> MigrateLegacyProfileAsync(
        BridgeAccountContext context, string action, string? previewId, bool replaceExisting,
        CancellationToken cancellationToken, StarBridge.HostRuntime.Auth.LegacyProfileCredential? credentials = null) =>
        Task.FromResult(new StarBridge.HostRuntime.Auth.LegacyProfileMigrationView("sourceUnavailable"));

    Task<PersonalProfileDocumentContract> UpdatePersonalProfileAsync(
        BridgeAccountContext context,
        PersonalProfilePresentationUpdateContract update,
        CancellationToken cancellationToken);

    Task<AccountBridgeOfficialFleetProjection> GetOfficialFleetAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken);

    Task<object> ReadDirectMessagesAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("directMessages.unavailable");

    Task<object> ReadDirectMessagePrivacyAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("directMessages.privacy_unavailable");

    Task<object> SaveDirectMessagePrivacyAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("directMessages.privacy_unavailable");

    Task<object> ReadFriendRequestPrivacyAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("friendRequests.privacy_unavailable");

    Task<object> SaveFriendRequestPrivacyAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("friendRequests.privacy_unavailable");

    Task<object> ReadRecentlyPlayedPrivacyAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("recentlyPlayed.privacy_unavailable");

    Task<object> SaveRecentlyPlayedPrivacyAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("recentlyPlayed.privacy_unavailable");

    Task<object> ReadCommunitiesAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> ExecuteCommunityAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> GetCommunityCreationOptionsAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> CreateCommunityAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> ReadCommunityWorkspaceAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> ReadCommunityLogsAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> DeleteCommunityLogAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> ReadCommunityChatAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReadCommunityAnnouncementsAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReadCommunityShipsAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReadCommunityHangarSharingAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    void ConfigureHangarSharingSource(Func<BridgeAccountContext, StarBridge.HostRuntime.Hangar.LocalHangarSnapshot> read) { }
    Task<StarBridge.HostRuntime.Hangar.HangarPublicationOutcome> UpdateSharedHangarAfterSaveAsync(
        BridgeAccountContext context, long generation, long revision, CancellationToken token) =>
        Task.FromResult(StarBridge.HostRuntime.Hangar.HangarPublicationOutcome.Rejected);
    Task<object> SaveCommunityHangarSharingAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReadCommunityShipImageAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReportCommunityShipImageAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReadCommunityAnnouncementDetailAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ManageCommunityAnnouncementsAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReadCommunityChatDetailAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> MarkCommunityChatReadAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> SendCommunityChatAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReadCommunityDisbandAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> DisbandCommunityAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> ReadCommunityMediaAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> ReadCommunityAdmissionsAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ManageCommunityAdmissionsAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReadCommunityProfileAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> SaveCommunityProfileAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> ReadCommunityRolesAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> SaveCommunityRolesAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReadCommunityMemberRoleAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> SaveCommunityMemberRoleAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReadCommunityMemberRemovalAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> RemoveCommunityMemberAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReadCommunityOwnershipTransferAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> TransferCommunityOwnershipAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> ReadCommunityOwnershipExitAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> LeaveCommunityWithSuccessorAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("communities.unavailable"));
    Task<object> PreviewCommunityInviteAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> AcceptCommunityInviteAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> SendCommunityInviteAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> ResumeCommunityInviteAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");
    Task<object> ReadCommunityInvitationOutboxAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("communities.unavailable");

    Task<object> MarkDirectMessagesReadAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("directMessages.unavailable");

    Task<object> SendDirectMessageAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("directMessages.unavailable");

    Task<StarBridge.HostRuntime.Friends.FriendCommandView> ExecuteFriendAsync(
        BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("friends.command_unavailable");

    Task<AccountSafetyView> ReadAccountSafetyAsync(
        BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<AccountSafetyView>(new AccountBridgeHostException("accountSafety.read_unavailable"));

    Task<object> ReadNotificationInboxAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("notificationInbox.unavailable"));
    Task<object> MarkNotificationInboxReadAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("notificationInbox.unavailable"));

    Task<object> SubmitAccountAppealAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("accountSafety.read_unavailable"));

    Task<StarBridge.HostRuntime.Friends.FriendsView> ReadFriendsAsync(
        BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<StarBridge.HostRuntime.Friends.FriendsView>(new AccountBridgeHostException("friends.read_unavailable"));

    Task<StarBridge.HostRuntime.PartyRooms.RoomDirectoryView> GetPartyRoomsAsync(
        BridgeAccountContext context, CancellationToken cancellationToken) =>
        Task.FromException<StarBridge.HostRuntime.PartyRooms.RoomDirectoryView>(
            new AccountBridgeHostException("party_rooms.read_unavailable"));

    Task<StarBridge.HostRuntime.PartyRooms.RoomCommandView> ExecutePartyRoomAsync(
        BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken cancellationToken) =>
        Task.FromException<StarBridge.HostRuntime.PartyRooms.RoomCommandView>(new AccountBridgeHostException("party_rooms.command_unavailable"));

    Task<object> LoginLegacyAsync(System.Text.Json.JsonElement payload, long generation, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("bridge.capability_unavailable"));

    Task<object> RedeemLegacyEntitlementsAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token) =>
        Task.FromException<object>(new AccountBridgeHostException("bridge.capability_unavailable"));

    Task<object> RecoverPasswordAsync(string action, System.Text.Json.JsonElement payload, CancellationToken token) =>
        throw new AccountBridgeHostException("bridge.capability_unavailable");

    Task<AccountBridgeCompatibilityProjection> GetCompatibilityStateAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken);

    Task<AccountBridgeCompatibilityProjection> LinkLegacyAccountAsync(
        BridgeAccountContext context,
        AccountBridgeLegacyCredential? credential,
        CancellationToken cancellationToken);

    Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken);

    Task<AccountBridgeProfileProjection> PatchPreferencesAsync(
        BridgeAccountContext context,
        AccountBridgePreferencePatch patch,
        CancellationToken cancellationToken);

    Task<bool> ClearProfileCacheAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken);

    Task<AccountBridgeIdentityProjection> GetGameIdentityPolicyAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken);
}

internal sealed class AccountBridgeHostException(
    string code,
    bool retryable = false) : Exception(code)
{
    internal string Code { get; } = code;

    internal bool Retryable { get; } = retryable;
}
