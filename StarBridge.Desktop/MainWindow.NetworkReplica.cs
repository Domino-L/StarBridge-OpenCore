using StarBridge.Core.Events;
using StarBridge.Core.FleetChat;
using StarBridge.Core.Fleets;
using StarBridge.Core.Presence;
using StarBridge.Core.State;
using System.Collections.ObjectModel;
using System.Net.Http;
using System.Windows.Media.Imaging;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void MergeNetworkFleetState(NetworkFleetSnapshot snapshot)
    {
        var snapshotCode = snapshot.Code?.Trim() ?? "";
        if (!string.Equals(_latestFleetSnapshotCode, snapshotCode, StringComparison.OrdinalIgnoreCase))
        {
            _latestFleetSnapshotCode = snapshotCode;
            _latestFleetSnapshotUpdatedAtUtc = DateTimeOffset.MinValue;
        }

        if (!FleetSnapshotOrderingPolicy.ShouldAccept(snapshot.LastUpdated, _latestFleetSnapshotUpdatedAtUtc))
        {
            return;
        }

        if (snapshot.LastUpdated > _latestFleetSnapshotUpdatedAtUtc)
        {
            _latestFleetSnapshotUpdatedAtUtc = snapshot.LastUpdated;
        }

        MergeNetworkFleetSquads(snapshot);

        if (string.IsNullOrWhiteSpace(snapshot.Name) || string.IsNullOrWhiteSpace(snapshot.Code))
        {
            return;
        }

        _fleetName = snapshot.Name.Trim();
        _fleetCode = snapshot.Code.Trim();
        _fleetChiefCommander = string.IsNullOrWhiteSpace(snapshot.Commander) ? _fleetChiefCommander : snapshot.Commander!;
        var incomingProfileRevision = snapshot.ProfileRevision;
        var isStaleProfileSnapshot = incomingProfileRevision < _fleetProfileRevision;
        if (incomingProfileRevision > _fleetProfileRevision)
        {
            _fleetProfileRevision = incomingProfileRevision;
        }
        if (!isStaleProfileSnapshot && !ShouldKeepLocalFleetProfileFields(snapshot))
        {
            ApplyNetworkFleetProfileFields(snapshot);
        }
        ApplyNetworkFleetLogo(snapshot);
        ApplyNetworkFleetBanner(snapshot);
        if (snapshot.MemberPermissions is not null)
        {
            MergeFleetMemberPermissions(snapshot.MemberPermissions);
        }
        MergeFleetMembers(snapshot.Members);
        MergeFleetEventLogs(snapshot.EventLog);
        MergeFleetTaskHistory(snapshot.TaskHistory);
        if (snapshot.Applications is not null)
        {
            _fleetApplicationSnapshots = snapshot.Applications;
            RefreshNavigationActivityBadges();
        }
        if (snapshot.Invites is not null)
        {
            _fleetInviteSnapshots = snapshot.Invites;
        }

        var isCommander = IsCurrentUserFleetCommander();
        var remoteHasNotice = !string.IsNullOrWhiteSpace(snapshot.NoticeTitle) ||
                              !string.IsNullOrWhiteSpace(snapshot.NoticeContent);
        var localHasNotice = !string.IsNullOrWhiteSpace(_fleetNoticeTitle) ||
                             !string.IsNullOrWhiteSpace(_fleetNoticeContent);
        var noticeContentChanged = !string.Equals(_fleetNoticeTitle, snapshot.NoticeTitle ?? "", StringComparison.Ordinal) ||
                                   !string.Equals(_fleetNoticeContent, snapshot.NoticeContent ?? "", StringComparison.Ordinal);
        if (remoteHasNotice || !localHasNotice || !isCommander)
        {
            _fleetNoticeTitle = snapshot.NoticeTitle ?? "";
            _fleetNoticeContent = snapshot.NoticeContent ?? "";
            _fleetNoticePublishedAt = !remoteHasNotice
                ? null
                : snapshot.NoticePublishedAt ??
                  (noticeContentChanged ? snapshot.LastUpdated : _fleetNoticePublishedAt);
        }

        var remoteHasTask = !string.IsNullOrWhiteSpace(snapshot.CurrentTaskTitle);
        var localHasTask = !string.IsNullOrWhiteSpace(_fleetCurrentTaskTitle);
        var remoteTaskRevision = Math.Max(0, snapshot.CurrentTaskNoticeRevision);
        var remoteTaskIsNewer = remoteTaskRevision > _fleetCurrentTaskNoticeRevision;
        var remoteTaskCleared = !remoteHasTask && localHasTask && remoteTaskRevision >= _fleetCurrentTaskNoticeRevision;
        if (remoteTaskIsNewer || remoteHasTask || remoteTaskCleared || !localHasTask || !isCommander)
        {
            _fleetCurrentTaskTitle = snapshot.CurrentTaskTitle ?? "";
            _fleetCurrentTaskBrief = snapshot.CurrentTaskBrief ?? "";
            _fleetCurrentTaskParticipants = snapshot.CurrentTaskParticipants ?? "";
            _fleetCurrentTaskRally = snapshot.CurrentTaskRally ?? "";
            _fleetCurrentTaskShip = snapshot.CurrentTaskShip ?? "";
            _fleetCurrentTaskTime = snapshot.CurrentTaskTime;
            _fleetCurrentTaskNoticeRevision = remoteTaskCleared
                ? remoteTaskRevision
                : Math.Max(_fleetCurrentTaskNoticeRevision, remoteTaskRevision);
        }

        if (snapshot.Ships is not null)
        {
            ReplaceRemoteFleetShips(FleetShipAvatarHydrator.Hydrate(snapshot.Ships, snapshot.Members));
        }

        if (snapshot.ActionPlans is not null)
        {
            _fleetActionPlans.Clear();
            foreach (var actionPlan in snapshot.ActionPlans)
            {
                var row = new FleetActionPlanRow(
                    actionPlan.Id,
                    actionPlan.Title,
                    actionPlan.Content,
                    actionPlan.StartTime,
                    actionPlan.NotifyMembers,
                    actionPlan.Status,
                    actionPlan.CanceledAt,
                    actionPlan.CanceledBy,
                    actionPlan.CancelReason,
                    actionPlan.ReachedAt,
                    actionPlan.CompletedAt,
                    actionPlan.CompletedBy,
                    actionPlan.CompletionMode,
                    actionPlan.UpdatedAt,
                    actionPlan.Version);

                foreach (var participant in actionPlan.Participants ?? [])
                {
                    row.Participants.Add(new ActionPlanParticipantRow(
                        participant.Callsign,
                        participant.GameName,
                        participant.AvatarImageData ?? participant.AvatarPath,
                        participant.Initials,
                        participant.ReminderRequested,
                        participant.ReminderSentAt));
                }

                row.RefreshParticipantSummary();
                _fleetActionPlans.Add(row);
            }
        }

        RebuildJoinedActionPlanIdsFromParticipants();
        SaveCurrentConfig();
        RenderState();
        RefreshFleetOperationalSurfaces();
        RefreshFleetMemberManagement();
        RefreshFleetApplications();
        RefreshFleetInvites();
        RefreshSquadActionButtons();
    }

    private void ApplyNetworkFleetProfileFields(NetworkFleetSnapshot snapshot)
    {
        var remoteDescription = NormalizeFleetDescription(snapshot.Description);
        if (!string.IsNullOrWhiteSpace(remoteDescription) || string.IsNullOrWhiteSpace(_fleetDescription))
        {
            _fleetDescription = remoteDescription;
        }

        if (!string.IsNullOrWhiteSpace(snapshot.Type))
        {
            _fleetType = snapshot.Type.Trim();
        }

        if (!string.IsNullOrWhiteSpace(snapshot.ActiveTime))
        {
            _fleetActiveTime = snapshot.ActiveTime.Trim();
        }

        if (!string.IsNullOrWhiteSpace(snapshot.JoinPolicy))
        {
            _fleetJoinPolicy = snapshot.JoinPolicy.Trim();
        }

        var remoteHasRecruitingFields = snapshot.RecruitingEnabled ||
                                        !string.IsNullOrWhiteSpace(snapshot.RecruitingTarget) ||
                                        !string.IsNullOrWhiteSpace(snapshot.RecruitingNote);
        if (remoteHasRecruitingFields || !_fleetRecruitingEnabled)
        {
            _fleetRecruitingEnabled = snapshot.RecruitingEnabled;
            if (!string.IsNullOrWhiteSpace(snapshot.RecruitingTarget) || string.IsNullOrWhiteSpace(_fleetRecruitingTarget))
            {
                _fleetRecruitingTarget = NormalizeFleetRecruitingTarget(snapshot.RecruitingTarget);
            }
        }

        _fleetInviteCodeCreationPolicy = FleetInvitationAccessPolicy.Normalize(snapshot.InviteCodeCreationPolicy);
        _fleetInvitationCardPolicy = FleetInvitationAccessPolicy.Normalize(snapshot.FleetInvitationCardPolicy);

        _fleetEmailNotificationsEnabled = snapshot.EmailNotificationsEnabled;
        _fleetPublicListingEnabled = snapshot.PublicListingEnabled;
        _fleetPublicMemberScaleMode = NormalizeFleetPublicMemberScaleMode(snapshot.PublicMemberScaleMode);
        _fleetPublicShipScaleMode = NormalizeFleetPublicShipScaleMode(snapshot.PublicShipScaleMode);
        _manageAllowPublicProfileView = true;
        _manageShowDescriptionPublic = snapshot.PublicShowDescription;
        _fleetPublicShowTags = snapshot.PublicShowTags;
        _fleetPublicShowActiveSystems = snapshot.PublicShowActiveSystems;
        _fleetPublicShowActivityTime = snapshot.PublicShowActivityTime;
        _fleetPublicShowExternalContacts = snapshot.PublicShowExternalContacts;
        SetSelectedFleetSystemIds(snapshot.ActiveSystemIds ?? [], refreshSelection: true);
        _fleetLanguage = string.IsNullOrWhiteSpace(snapshot.Language) ? _fleetLanguage : snapshot.Language.Trim();
        _fleetWebsiteUrl = NormalizeOptionalField(snapshot.WebsiteUrl);
        SetFleetExternalContacts((snapshot.ExternalContacts ?? [])
            .Select(contact => new LocalFleetExternalContact(contact.Platform, contact.Value)));

        if (!string.IsNullOrWhiteSpace(snapshot.TimeZoneId))
        {
            _fleetTimeZoneId = snapshot.TimeZoneId.Trim();
        }

        if (!string.IsNullOrWhiteSpace(snapshot.ActivityCadence))
        {
            _fleetActivityCadence = NormalizeManageProfileOption(snapshot.ActivityCadence, _fleetActivityCadence);
        }

        if (snapshot.ActivityWindows is { Length: > 0 })
        {
            LoadFleetActivityWindows(
                ToLocalFleetActivityWindows(snapshot.ActivityWindows),
                snapshot.ActiveDaysDescription,
                snapshot.ActiveTime);
        }
        else
        {
            if (!string.IsNullOrWhiteSpace(snapshot.ActiveDaysDescription))
            {
                _fleetActiveDaysDescription = snapshot.ActiveDaysDescription.Trim();
            }
        }

        if (!_isFleetRoleGroupsDirty && snapshot.RoleGroups is { Length: > 0 })
        {
            LoadFleetRoleGroupDefinitions(snapshot.RoleGroups.Select(ToLocalFleetRoleGroup));
        }
    }

    private bool ShouldKeepLocalFleetProfileFields(NetworkFleetSnapshot snapshot)
    {
        if (_isManageProfileEditMode && _isManageProfileDirty)
        {
            return true;
        }

        if (_fleetProfileSyncEchoProtectedUntilUtc == DateTimeOffset.MinValue)
        {
            return false;
        }

        if (DateTimeOffset.UtcNow > _fleetProfileSyncEchoProtectedUntilUtc)
        {
            ClearFleetProfileSyncEchoProtection();
            return false;
        }

        if (PendingFleetProfileMatches(snapshot))
        {
            if (_fleetProfileSyncEchoConfirmedAtUtc == DateTimeOffset.MinValue)
            {
                _fleetProfileSyncEchoConfirmedAtUtc = DateTimeOffset.UtcNow;
                _fleetProfileSyncEchoProtectedUntilUtc = _fleetProfileSyncEchoConfirmedAtUtc.AddSeconds(8);
            }

            // Keep the local values briefly after the authoritative echo. An older pull that
            // started before this save can otherwise arrive later and restore the previous state.
            return true;
        }

        return true;
    }

    private bool PendingFleetProfileMatches(NetworkFleetSnapshot snapshot)
    {
        return FleetProfileFieldEquals(snapshot.Description, _pendingFleetProfileDescription) &&
               FleetProfileFieldEquals(snapshot.Type, _pendingFleetProfileType) &&
               FleetProfileFieldEquals(snapshot.ActiveTime, _pendingFleetProfileActiveTime) &&
               FleetProfileFieldEquals(snapshot.JoinPolicy, _pendingFleetProfileJoinPolicy) &&
               (!_pendingFleetProfileRecruitingEnabled.HasValue ||
                snapshot.RecruitingEnabled == _pendingFleetProfileRecruitingEnabled.Value) &&
               FleetProfileFieldEquals(snapshot.RecruitingTarget, _pendingFleetProfileRecruitingTarget) &&
               FleetProfileFieldEquals(
                   FleetInvitationAccessPolicy.Normalize(snapshot.InviteCodeCreationPolicy),
                   _pendingFleetInviteCodeCreationPolicy) &&
               FleetProfileFieldEquals(
                   FleetInvitationAccessPolicy.Normalize(snapshot.FleetInvitationCardPolicy),
                   _pendingFleetInvitationCardPolicy) &&
               FleetProfileFieldEquals(snapshot.ActiveDaysDescription, _pendingFleetProfileActiveDaysDescription) &&
               FleetProfileFieldEquals(snapshot.ActivityCadence, _pendingFleetProfileActivityCadence) &&
               FleetProfileFieldEquals(snapshot.TimeZoneId, _pendingFleetProfileTimeZoneId) &&
               string.Equals(
                   BuildFleetActivityWindowsKey(snapshot.ActivityWindows),
                   _pendingFleetProfileActivityWindowsKey ?? "",
                   StringComparison.Ordinal) &&
               (!_pendingFleetProfileEmailNotificationsEnabled.HasValue ||
                snapshot.EmailNotificationsEnabled == _pendingFleetProfileEmailNotificationsEnabled.Value) &&
               (!_pendingFleetPublicListingEnabled.HasValue ||
                snapshot.PublicListingEnabled == _pendingFleetPublicListingEnabled.Value) &&
               FleetProfileFieldEquals(snapshot.PublicMemberScaleMode, _pendingFleetPublicMemberScaleMode) &&
               FleetProfileFieldEquals(snapshot.PublicShipScaleMode, _pendingFleetPublicShipScaleMode) &&
               (!_pendingFleetPublicProfileEnabled.HasValue ||
                snapshot.PublicProfileEnabled == _pendingFleetPublicProfileEnabled.Value) &&
               (!_pendingFleetPublicShowDescription.HasValue ||
                snapshot.PublicShowDescription == _pendingFleetPublicShowDescription.Value) &&
               (!_pendingFleetPublicShowTags.HasValue ||
                snapshot.PublicShowTags == _pendingFleetPublicShowTags.Value) &&
               (!_pendingFleetPublicShowActiveSystems.HasValue ||
                snapshot.PublicShowActiveSystems == _pendingFleetPublicShowActiveSystems.Value) &&
               (!_pendingFleetPublicShowActivityTime.HasValue ||
                snapshot.PublicShowActivityTime == _pendingFleetPublicShowActivityTime.Value) &&
               (!_pendingFleetPublicShowExternalContacts.HasValue ||
                snapshot.PublicShowExternalContacts == _pendingFleetPublicShowExternalContacts.Value);
    }

    private static bool FleetProfileFieldEquals(string? left, string? right)
    {
        return string.Equals(
            NormalizeFleetProfileFieldForComparison(left),
            NormalizeFleetProfileFieldForComparison(right),
            StringComparison.Ordinal);
    }

    private static string NormalizeFleetProfileFieldForComparison(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? "" : value.Trim();
    }

    private void ProtectFleetProfileUntilServerEcho()
    {
        _pendingFleetProfileDescription = _fleetDescription;
        _pendingFleetProfileType = _fleetType;
        _pendingFleetProfileActiveTime = _fleetActiveTime;
        _pendingFleetProfileJoinPolicy = _fleetJoinPolicy;
        _pendingFleetProfileRecruitingEnabled = _fleetRecruitingEnabled;
        _pendingFleetProfileRecruitingTarget = _fleetRecruitingTarget;
        _pendingFleetInviteCodeCreationPolicy = _fleetInviteCodeCreationPolicy;
        _pendingFleetInvitationCardPolicy = _fleetInvitationCardPolicy;
        _pendingFleetProfileEmailNotificationsEnabled = _fleetEmailNotificationsEnabled;
        _pendingFleetProfileActivityWindowsKey = BuildFleetActivityWindowsKey(BuildNetworkFleetActivityWindows());
        _pendingFleetProfileActiveDaysDescription = _fleetActiveDaysDescription;
        _pendingFleetProfileActivityCadence = _fleetActivityCadence;
        _pendingFleetProfileTimeZoneId = _fleetTimeZoneId;
        _pendingFleetPublicListingEnabled = _fleetPublicListingEnabled;
        _pendingFleetPublicMemberScaleMode = _fleetPublicMemberScaleMode;
        _pendingFleetPublicShipScaleMode = _fleetPublicShipScaleMode;
        _pendingFleetPublicProfileEnabled = _manageAllowPublicProfileView;
        _pendingFleetPublicShowDescription = _manageShowDescriptionPublic;
        _pendingFleetPublicShowTags = _fleetPublicShowTags;
        _pendingFleetPublicShowActiveSystems = _fleetPublicShowActiveSystems;
        _pendingFleetPublicShowActivityTime = _fleetPublicShowActivityTime;
        _pendingFleetPublicShowExternalContacts = _fleetPublicShowExternalContacts;
        _fleetProfileSyncEchoConfirmedAtUtc = DateTimeOffset.MinValue;
        _fleetProfileSyncEchoProtectedUntilUtc = DateTimeOffset.UtcNow.AddMinutes(3);
    }

    private void ClearFleetProfileSyncEchoProtection()
    {
        _pendingFleetProfileDescription = null;
        _pendingFleetProfileType = null;
        _pendingFleetProfileActiveTime = null;
        _pendingFleetProfileJoinPolicy = null;
        _pendingFleetProfileRecruitingEnabled = null;
        _pendingFleetProfileRecruitingTarget = null;
        _pendingFleetInviteCodeCreationPolicy = null;
        _pendingFleetInvitationCardPolicy = null;
        _pendingFleetProfileEmailNotificationsEnabled = null;
        _pendingFleetProfileActivityWindowsKey = null;
        _pendingFleetProfileActiveDaysDescription = null;
        _pendingFleetProfileActivityCadence = null;
        _pendingFleetProfileTimeZoneId = null;
        _pendingFleetPublicListingEnabled = null;
        _pendingFleetPublicMemberScaleMode = null;
        _pendingFleetPublicShipScaleMode = null;
        _pendingFleetPublicProfileEnabled = null;
        _pendingFleetPublicShowDescription = null;
        _pendingFleetPublicShowTags = null;
        _pendingFleetPublicShowActiveSystems = null;
        _pendingFleetPublicShowActivityTime = null;
        _pendingFleetPublicShowExternalContacts = null;
        _fleetProfileSyncEchoConfirmedAtUtc = DateTimeOffset.MinValue;
        _fleetProfileSyncEchoProtectedUntilUtc = DateTimeOffset.MinValue;
    }

    private static LocalFleetActivityWindow[] ToLocalFleetActivityWindows(NetworkFleetActivityWindowSnapshot[]? windows)
    {
        return (windows ?? [])
            .Select(window => new LocalFleetActivityWindow(
                window.Days,
                window.StartTime,
                window.EndTime,
                window.EndsNextDay))
            .ToArray();
    }

    private static string BuildFleetActivityWindowsKey(IEnumerable<NetworkFleetActivityWindowSnapshot>? windows)
    {
        return string.Join(
            "|",
            (windows ?? [])
                .Select(window =>
                {
                    var days = string.Join(",", NormalizeFleetActivityDays(window.Days));
                    var start = NormalizeFleetActivityClockText(window.StartTime, DefaultFleetActivityStartTime);
                    var end = NormalizeFleetActivityClockText(window.EndTime, DefaultFleetActivityEndTime);
                    var nextDay = ShouldFleetActivityEndNextDay(start, end, window.EndsNextDay);
                    return $"{days}@{start}-{(nextDay ? "+1" : "0")}{end}";
                }));
    }

    private void RebuildJoinedActionPlanIdsFromParticipants()
    {
        var identities = EnumerateLocalIdentities()
            .Where(identity => !string.IsNullOrWhiteSpace(identity))
            .Select(identity => identity.Trim())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (identities.Count == 0)
        {
            return;
        }

        _joinedActionPlanIds.Clear();
        foreach (var plan in _fleetActionPlans)
        {
            if (plan.IsCanceled)
            {
                continue;
            }

            var joined = plan.Participants.Any(participant =>
                IsLocalPlayerIdentity(participant.GameName, participant.Callsign) ||
                (!string.IsNullOrWhiteSpace(participant.GameName) && identities.Contains(participant.GameName)) ||
                (!string.IsNullOrWhiteSpace(participant.Callsign) && identities.Contains(participant.Callsign)));

            if (joined)
            {
                _joinedActionPlanIds.Add(plan.Id);
            }
        }
    }

    private void MergeFleetMemberPermissions(NetworkFleetMemberPermissionSnapshot[]? permissions)
    {
        _fleetMemberPermissions.Clear();

        foreach (var permission in permissions ?? [])
        {
            if (string.IsNullOrWhiteSpace(permission.GameName))
            {
                continue;
            }

            var safeGameName = NormalizeDisplayIdentityPart(permission.GameName);
            var safeCallsign = NormalizeDisplayIdentityPart(permission.Callsign);
            if (string.IsNullOrWhiteSpace(safeGameName))
            {
                safeGameName = safeCallsign;
            }

            if (string.IsNullOrWhiteSpace(safeGameName))
            {
                continue;
            }

            _fleetMemberPermissions[safeGameName] = new LocalFleetMemberPermission(
                safeGameName,
                safeCallsign,
                NormalizeRoleTitle(permission.RoleTitle),
                permission.PermissionEnabled,
                permission.CanRemoveMembers,
                permission.CanPublishTasks,
                permission.CanPublishPlans,
                permission.CanManageFleetInfo,
                permission.UpdatedAt,
                NormalizeRoleGroupKey(permission.RoleGroupKey, permission.RoleTitle),
                permission.ExtraAllowedPermissions,
                permission.ExtraDeniedPermissions);
        }
    }

    private void MergeFleetMembers(NetworkFleetMemberSnapshot[]? members)
    {
        var safeMembers = FleetMemberDisplaySanitizer.Canonicalize(members);
        _fleetMemberJoinedAtByIdentity.Clear();
        foreach (var emailKey in _networkSnapshots.Keys.Where(FleetMemberDisplaySanitizer.IsEmail).ToArray())
        {
            _networkSnapshots.Remove(emailKey);
        }

        _fleetState.RemovePlayersExcept(safeMembers
            .Select(member => GetNetworkSnapshotKey(member.AccountId, member.GameName))
            .Append(_localPlayer));
        foreach (var member in safeMembers)
        {
            if (string.IsNullOrWhiteSpace(member.GameName))
            {
                continue;
            }

            var gameName = member.GameName.Trim();
            RegisterFleetMemberJoinedAt(member);
            var memberSnapshotKey = GetNetworkSnapshotKey(member.AccountId, gameName);
            _networkSnapshots.TryGetValue(memberSnapshotKey, out var previousMemberSnapshot);
            var publicProfileId = UserAvatarProfileIdentityPolicy.PreserveKnownPublicId(
                member.AccountId,
                previousMemberSnapshot?.AccountId);
            var memberSnapshot = new NetworkPlayerSnapshot(
                gameName,
                DisplayCallsign(member.Callsign, gameName),
                _fleetName,
                string.IsNullOrWhiteSpace(member.SquadName) ? "Unassigned" : member.SquadName,
                member.Online,
                string.IsNullOrWhiteSpace(member.Ship) ? "Unknown" : member.Ship,
                string.IsNullOrWhiteSpace(member.Ship) ||
                member.Ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase)
                    ? "None"
                    : "Low",
                string.IsNullOrWhiteSpace(member.Location) ? "Unknown" : member.Location,
                string.IsNullOrWhiteSpace(member.LocationConfidence) ? "Low" : member.LocationConfidence,
                member.LastUpdated == default ? DateTimeOffset.UtcNow : member.LastUpdated,
                member.AvatarImageData,
                null,
                ServerShard: member.ServerShard,
                ServerRegion: member.ServerRegion,
                LiveStatus: member.LiveStatus,
                AccountId: publicProfileId,
                SharedEventTypes: previousMemberSnapshot?.SharedEventTypes ?? (int)PlayerSharedEventTypes.All,
                SharedEvents: previousMemberSnapshot?.SharedEvents);
            memberSnapshotKey = GetNetworkSnapshotKey(memberSnapshot);
            _networkSnapshots[memberSnapshotKey] = memberSnapshot;
            ApplyFleetMemberSnapshotToState(memberSnapshot);

            if (!_fleetMemberPermissions.ContainsKey(gameName))
            {
                _fleetMemberPermissions[gameName] = new LocalFleetMemberPermission(
                    gameName,
                    DisplayCallsign(member.Callsign, gameName),
                    NormalizeRoleTitle(member.RoleTitle),
                    false,
                    false,
                    false,
                    false,
                    false,
                    member.LastUpdated == default ? DateTimeOffset.UtcNow : member.LastUpdated,
                    NormalizeRoleGroupKey(null, member.RoleTitle));
            }
        }

    }

    private void RegisterFleetMemberJoinedAt(NetworkFleetMemberSnapshot member)
    {
        if (member.JoinedAt == default || member.JoinedAt == DateTimeOffset.MinValue)
        {
            return;
        }

        var joinedAt = member.JoinedAt.ToUniversalTime();
        if (IsLocalPlayer(member.GameName) ||
            !string.IsNullOrWhiteSpace(_accountId) &&
            !string.IsNullOrWhiteSpace(member.AccountId) &&
            _accountId.Equals(member.AccountId, StringComparison.OrdinalIgnoreCase))
        {
            _fleetJoinedAtUtc = joinedAt;
        }

        foreach (var key in new[]
                 {
                     BuildFleetMemberJoinIdentityKey("account", member.AccountId),
                     BuildFleetMemberJoinIdentityKey("game", member.GameName),
                     BuildFleetMemberJoinIdentityKey("callsign", member.Callsign)
                 }
                 .Where(key => !string.IsNullOrWhiteSpace(key)))
        {
            if (!_fleetMemberJoinedAtByIdentity.TryGetValue(key, out var existing) || joinedAt < existing)
            {
                _fleetMemberJoinedAtByIdentity[key] = joinedAt;
            }
        }
    }

    private static string BuildFleetMemberJoinIdentityKey(string kind, string? value)
    {
        return string.IsNullOrWhiteSpace(value)
            ? ""
            : $"{kind}:{value.Trim()}";
    }

    private void ApplyFleetMemberSnapshotToState(NetworkPlayerSnapshot snapshot)
    {
        if (string.IsNullOrWhiteSpace(snapshot.Name) || IsLocalNetworkSnapshot(snapshot))
        {
            return;
        }

        var snapshotKey = GetNetworkSnapshotKey(snapshot);
        var timestamp = snapshot.LastUpdated == default ? DateTimeOffset.UtcNow : snapshot.LastUpdated;
        _fleetState.Apply(new FleetEvent(
            snapshot.Online ? FleetEventType.PlayerOnline : FleetEventType.PlayerOffline,
            snapshotKey,
            Timestamp: timestamp));

        if (!snapshot.Online)
        {
            return;
        }

        if (!string.IsNullOrWhiteSpace(snapshot.Ship) &&
            !snapshot.Ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            _fleetState.Apply(new FleetEvent(
                FleetEventType.PlayerShipControlSignal,
                snapshotKey,
                Ship: snapshot.Ship,
                Timestamp: timestamp));
        }

        if (!string.IsNullOrWhiteSpace(snapshot.Location) &&
            !snapshot.Location.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            _fleetState.Apply(new FleetEvent(
                FleetEventType.PlayerLocationChanged,
                snapshotKey,
                Location: snapshot.Location,
                LocationEvidenceScore: LocationEvidenceScoreFromConfidence(snapshot.LocationConfidence),
                LocationEvidence: "Fleet member sync",
                Timestamp: timestamp));
        }
    }

    private void MergeFleetEventLogs(NetworkFleetEventLogSnapshot[]? eventLogs)
    {
        if (eventLogs is null)
        {
            return;
        }

        var ordered = eventLogs
            .Where(item => !string.IsNullOrWhiteSpace(item.Id))
            .Where(item => !IsPersonalPlanParticipationLog(item.Type, item.Title))
            .Select(item => new FleetEventLogRow(
                item.Id.Trim(),
                item.Timestamp == default ? DateTimeOffset.UtcNow : item.Timestamp,
                string.IsNullOrWhiteSpace(item.Type) ? "舰队" : item.Type,
                SanitizeFleetEventText(item.Title),
                SanitizeFleetEventText(item.Detail),
                EndTimestamp: item.EndTimestamp,
                OccurrenceCount: Math.Max(1, item.OccurrenceCount)))
            .OrderByDescending(row => row.EffectiveEndTimestamp)
            .Take(500)
            .ToArray();

        if (_allFleetEventLogs.Count == ordered.Length &&
            _allFleetEventLogs.Zip(ordered).All(pair =>
                pair.First.Id.Equals(pair.Second.Id, StringComparison.OrdinalIgnoreCase) &&
                pair.First.Timestamp == pair.Second.Timestamp &&
                pair.First.Type.Equals(pair.Second.Type, StringComparison.Ordinal) &&
                pair.First.Title.Equals(pair.Second.Title, StringComparison.Ordinal) &&
                pair.First.Detail.Equals(pair.Second.Detail, StringComparison.Ordinal) &&
                pair.First.EffectiveEndTimestamp == pair.Second.EffectiveEndTimestamp &&
                pair.First.OccurrenceCount == pair.Second.OccurrenceCount))
        {
            return;
        }

        _allFleetEventLogs.Clear();
        foreach (var row in ordered)
        {
            _allFleetEventLogs.Add(row);
        }

        ApplyFleetEventLogFilter();
    }

    private void MergeFleetTaskHistory(NetworkFleetTaskHistorySnapshot[]? taskHistory)
    {
        var changed = false;
        foreach (var item in taskHistory ?? [])
        {
            if (string.IsNullOrWhiteSpace(item.Key) || string.IsNullOrWhiteSpace(item.Title))
            {
                continue;
            }

            var row = new FleetTaskHistoryRow(
                item.Key.Trim(),
                item.Title.Trim(),
                string.IsNullOrWhiteSpace(item.Brief) ? "未指定" : item.Brief.Trim(),
                string.IsNullOrWhiteSpace(item.Status) ? "进行中" : item.Status.Trim(),
                string.IsNullOrWhiteSpace(item.Participants) ? "参与范围 / 未指定" : item.Participants.Trim(),
                string.IsNullOrWhiteSpace(item.Rally) ? "集结点 / 未发布" : item.Rally.Trim(),
                string.IsNullOrWhiteSpace(item.RequiredShip) ? "指定舰船 / 无" : item.RequiredShip.Trim(),
                string.IsNullOrWhiteSpace(item.PublishedAtText) ? "" : item.PublishedAtText.Trim());
            var existingIndex = _fleetTaskHistory
                .Select((task, index) => new { task, index })
                .FirstOrDefault(entry => entry.task.Key.Equals(row.Key, StringComparison.OrdinalIgnoreCase))
                ?.index;

            if (existingIndex is int index)
            {
                if (!_fleetTaskHistory[index].Equals(row))
                {
                    _fleetTaskHistory[index] = row;
                    changed = true;
                }
            }
            else
            {
                _fleetTaskHistory.Add(row);
                changed = true;
            }
        }

        if (!changed)
        {
            return;
        }

        var ordered = _fleetTaskHistory
            .Take(200)
            .ToArray();
        _fleetTaskHistory.Clear();
        foreach (var row in ordered)
        {
            _fleetTaskHistory.Add(row);
        }

        RefreshTaskManagementPanel();
    }

    private void ApplyNetworkSnapshot(NetworkPlayerSnapshot snapshot)
    {
        if (string.IsNullOrWhiteSpace(snapshot.Name) || IsLocalNetworkSnapshot(snapshot))
        {
            return;
        }

        if (!_hasFleet)
        {
            _networkSnapshots.Remove(GetNetworkSnapshotKey(snapshot));
            return;
        }

        var snapshotKey = GetNetworkSnapshotKey(snapshot);
        _networkSnapshots.TryGetValue(snapshotKey, out var previousSnapshot);
        var wasInFleet = previousSnapshot is not null && IsSameFleet(previousSnapshot.Fleet);
        var isInFleet = IsSameFleet(snapshot.Fleet);
        _networkSnapshots[snapshotKey] = snapshot;
        ReplaceRemoteFleetShipsForOwner(
            snapshot.Name,
            snapshot.Callsign,
            isInFleet ? BuildFleetShipsFromPlayerSnapshot(snapshot) : []);

        if (_hasFleet && !isInFleet)
        {
            return;
        }

        QueueSharedLifeEventNotification(snapshot, previousSnapshot);

        _fleetState.Apply(new FleetEvent(
            snapshot.Online ? FleetEventType.PlayerOnline : FleetEventType.PlayerOffline,
            snapshotKey,
            Timestamp: snapshot.LastUpdated));

        if (!snapshot.Online)
        {
            return;
        }

        if (!string.IsNullOrWhiteSpace(snapshot.Ship) &&
            !snapshot.Ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            _fleetState.Apply(new FleetEvent(
                FleetEventType.PlayerShipControlSignal,
                snapshotKey,
                Ship: snapshot.Ship,
                Timestamp: snapshot.LastUpdated));
        }

        if (!string.IsNullOrWhiteSpace(snapshot.Location) &&
            !snapshot.Location.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            _fleetState.Apply(new FleetEvent(
                FleetEventType.PlayerLocationChanged,
                snapshotKey,
                Location: snapshot.Location,
                LocationEvidenceScore: LocationEvidenceScoreFromConfidence(snapshot.LocationConfidence),
                LocationEvidence: "Network relay",
                Timestamp: snapshot.LastUpdated));
        }
    }

    private void QueueSharedLifeEventNotification(
        NetworkPlayerSnapshot snapshot,
        NetworkPlayerSnapshot? previousSnapshot)
    {
        if (_overlayWindow is null ||
            !_overlaySettings.ShowEventNotifications ||
            !_overlaySettings.EventNotificationTypes.HasFlag(OverlayEventNotificationTypes.DeathAndRespawn))
        {
            return;
        }

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var player = FormatPlayerForUser(snapshot.Name);
        foreach (var eventType in NetworkSharedLifeEventPolicy.ResolveNew(
                     snapshot,
                     previousSnapshot,
                     DateTimeOffset.UtcNow))
        {
            var notification = OverlayGameEventNotificationPolicy.Create(eventType, player, zh);
            if (notification is null)
            {
                continue;
            }

            _overlayWindow.QueueGameEventNotification(
                notification.EventType,
                notification.Title,
                notification.Detail,
                notification.Important,
                notification.Positive);
        }
    }

    private bool IsLocalNetworkSnapshot(NetworkPlayerSnapshot snapshot)
    {
        if (!string.IsNullOrWhiteSpace(snapshot.AccountId) && !string.IsNullOrWhiteSpace(_accountId))
        {
            return snapshot.AccountId.Equals(_accountId, StringComparison.OrdinalIgnoreCase);
        }

        return !string.IsNullOrWhiteSpace(_localPlayer) &&
               snapshot.Name.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase);
    }

    private static string GetNetworkSnapshotKey(NetworkPlayerSnapshot snapshot) =>
        GetNetworkSnapshotKey(snapshot.AccountId, snapshot.Name);

    private static string GetNetworkSnapshotKey(string? accountId, string gameName) =>
        string.IsNullOrWhiteSpace(accountId)
            ? gameName.Trim()
            : $"account:{accountId.Trim()}";

    private void ApplyLocalNetworkSnapshot(NetworkPlayerSnapshot snapshot)
    {
        if (!IsLocalNetworkSnapshot(snapshot))
        {
            return;
        }

        var changed = false;
        var joinedDifferentFleetFromSnapshot = false;
        if (string.IsNullOrWhiteSpace(_callsign) && !string.IsNullOrWhiteSpace(snapshot.Callsign))
        {
            _callsign = snapshot.Callsign!;
            CallsignBox.Text = _callsign;
            changed = true;
        }

        var snapshotFleet = snapshot.Fleet?.Trim();
        var snapshotHasFleet = !string.IsNullOrWhiteSpace(snapshotFleet) &&
                               !snapshotFleet.Equals("No Fleet", StringComparison.OrdinalIgnoreCase);
        if (!snapshotHasFleet)
        {
            if (_hasFleet)
            {
                MarkFleetDirectorySyncPending();
                return;
            }
        }
        else if (_hasFleet && !IsSameFleet(snapshotFleet))
        {
            MarkFleetDirectorySyncPending();
            return;
        }

        if (_hasFleet)
        {
            var snapshotSquad = joinedDifferentFleetFromSnapshot ? "Unassigned" : snapshot.Squad?.Trim();
            if (string.IsNullOrWhiteSpace(snapshotSquad) ||
                snapshotSquad.Equals("Unassigned", StringComparison.OrdinalIgnoreCase))
            {
                if (_joinedSquad is not null)
                {
                    var previousJoinedSquad = _joinedSquad;
                    _joinedSquad = null;
                    if (_selectedSquad is not null &&
                        _selectedSquad.Name.Equals(previousJoinedSquad.Name, StringComparison.OrdinalIgnoreCase))
                    {
                        _selectedSquad = null;
                    }

                    SquadSelectionList.SelectedItem = _selectedSquad;
                    changed = true;
                }
            }
            else
            {
                var squad = _squads.FirstOrDefault(item =>
                    item.Name.Equals(snapshotSquad, StringComparison.OrdinalIgnoreCase));
                if (squad is not null && !ReferenceEquals(_joinedSquad, squad))
                {
                    _joinedSquad = squad;
                    _selectedSquad = squad;
                    SquadSelectionList.SelectedItem = _selectedSquad;
                    changed = true;
                }
            }
        }

        if (_hasFleet && _joinedSquad is not null && _selectedSquad is null)
        {
            _selectedSquad = _joinedSquad;
            SquadSelectionList.SelectedItem = _selectedSquad;
            changed = true;
        }

        if (!changed)
        {
            return;
        }

        SaveCurrentConfig();
        RenderState();
        RefreshFleetInfoPanel();
        RefreshFleetMemberManagement();
        RefreshOverlayWindow();
    }

    private bool IsSameFleet(string? fleet)
    {
        if (!_hasFleet || string.IsNullOrWhiteSpace(fleet))
        {
            return false;
        }

        return fleet.Equals(_fleetName, StringComparison.OrdinalIgnoreCase) ||
               fleet.Equals(_fleetCode, StringComparison.OrdinalIgnoreCase);
    }

    private void MarkFleetMembershipChanged()
    {
        _fleetMembershipChangedAtUtc = DateTimeOffset.UtcNow;
        if (_hasFleet)
        {
            _fleetJoinedAtUtc = _fleetMembershipChangedAtUtc;
        }
    }

    private void MarkFleetDirectorySyncPending()
    {
        if (_hasFleet)
        {
            _fleetDirectorySyncPending = true;
        }
    }

    private bool IsFleetMembershipSyncGraceActive()
    {
        return _hasFleet &&
               (DateTimeOffset.UtcNow - _fleetMembershipChangedAtUtc).TotalSeconds <= FleetMembershipSyncGraceSeconds;
    }

    private bool ShouldPreserveLocalFleetDuringServerCatchup()
    {
        return _hasFleet &&
               (IsFleetMembershipSyncGraceActive() ||
                _fleetDirectorySyncPending ||
                HasCurrentFleetMembershipEvidenceOnRelay());
    }

    private bool HasCurrentFleetMembershipEvidenceOnRelay()
    {
        if (!_hasFleet || _allNetworkFleets.Count == 0)
        {
            return false;
        }

        foreach (var card in _allNetworkFleets)
        {
            var snapshot = card.Snapshot;
            if (!IsSameFleet(snapshot.Name) && !IsSameFleet(snapshot.Code))
            {
                continue;
            }

            if (FleetSnapshotContainsLocalPlayer(snapshot))
            {
                return true;
            }
        }

        return false;
    }

    private bool FleetSnapshotContainsLocalPlayer(NetworkFleetSnapshot snapshot)
    {
        var identities = EnumerateLocalIdentities()
            .Where(identity => !string.IsNullOrWhiteSpace(identity))
            .Select(identity => identity.Trim())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (identities.Count == 0)
        {
            return false;
        }

        return (snapshot.Members ?? [])
            .Any(member => EnumerateIdentityAliases(member.GameName, member.Callsign)
                .Any(identities.Contains));
    }

    private bool ShouldRetryPendingFleetDirectorySync()
    {
        return _hasFleet &&
               _fleetDirectorySyncPending &&
               IsLoggedIn &&
               (DateTimeOffset.UtcNow - _lastFleetDirectorySyncAttemptAtUtc).TotalSeconds >= FleetDirectoryRetrySeconds;
    }

    private async Task RetryPendingFleetDirectorySyncAsync(bool silent = true)
    {
        if (!ShouldRetryPendingFleetDirectorySync())
        {
            return;
        }

        await PushFleetDirectoryAsync(silent);
    }

    private void MergeNetworkFleetSquads(NetworkFleetSnapshot snapshot)
    {
        var changed = false;
        var remoteSquadSnapshots = snapshot.Squads ?? [];
        var remoteSquadNames = remoteSquadSnapshots
            .Where(squad => !string.IsNullOrWhiteSpace(squad.Name))
            .Select(squad => squad.Name.Trim())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        if (snapshot.Squads is not null)
        {
            var removedSquadNames = _squads
                .Where(squad => !remoteSquadNames.Contains(squad.Name) &&
                                !HasRecentLocalSquadEdit(squad.Name))
                .Select(squad => squad.Name)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);

            if (removedSquadNames.Count > 0)
            {
                for (var index = _squads.Count - 1; index >= 0; index--)
                {
                    if (removedSquadNames.Contains(_squads[index].Name))
                    {
                        _squads.RemoveAt(index);
                        changed = true;
                    }
                }

                if (_joinedSquad is not null && removedSquadNames.Contains(_joinedSquad.Name))
                {
                    _joinedSquad = null;
                }

                if (_selectedSquad is not null && removedSquadNames.Contains(_selectedSquad.Name))
                {
                    _selectedSquad = _joinedSquad;
                    SquadSelectionList.SelectedItem = _selectedSquad;
                }
            }
        }

        foreach (var squadSnapshot in remoteSquadSnapshots)
        {
            if (string.IsNullOrWhiteSpace(squadSnapshot.Name))
            {
                continue;
            }

            var existing = _squads.FirstOrDefault(squad =>
                squad.Name.Equals(squadSnapshot.Name, StringComparison.OrdinalIgnoreCase));
            if (existing is null)
            {
                _squads.Add(new SquadRow
                {
                    Id = FleetChatIdentity.NormalizeSquadId(squadSnapshot.Id, squadSnapshot.Name),
                    Name = squadSnapshot.Name,
                    Icon = GetInitials(squadSnapshot.Name),
                    Commander = string.IsNullOrWhiteSpace(squadSnapshot.Commander) ? "Unassigned" : squadSnapshot.Commander!,
                    Mission = string.IsNullOrWhiteSpace(squadSnapshot.Mission) ? "Standby" : squadSnapshot.Mission!,
                    RallyPoint = string.IsNullOrWhiteSpace(squadSnapshot.RallyPoint) ? "Use Global" : squadSnapshot.RallyPoint!,
                    Type = string.IsNullOrWhiteSpace(squadSnapshot.Type) ? "Assault" : squadSnapshot.Type!,
                    Description = string.IsNullOrWhiteSpace(squadSnapshot.Description) ? "No squad briefing yet." : squadSnapshot.Description!,
                    EmblemPath = SaveNetworkSquadEmblem(snapshot, squadSnapshot),
                    UpdatedAt = squadSnapshot.UpdatedAt
                });
                changed = true;
                continue;
            }

            if (ShouldPreserveLocalSquad(existing, squadSnapshot))
            {
                continue;
            }

            var nextId = FleetChatIdentity.NormalizeSquadId(squadSnapshot.Id, squadSnapshot.Name);
            var nextCommander = string.IsNullOrWhiteSpace(squadSnapshot.Commander) ? existing.Commander : squadSnapshot.Commander!;
            var nextMission = string.IsNullOrWhiteSpace(squadSnapshot.Mission) ? existing.Mission : squadSnapshot.Mission!;
            var nextRallyPoint = string.IsNullOrWhiteSpace(squadSnapshot.RallyPoint) ? existing.RallyPoint : squadSnapshot.RallyPoint!;
            var nextType = string.IsNullOrWhiteSpace(squadSnapshot.Type) ? existing.Type : squadSnapshot.Type!;
            var nextDescription = string.IsNullOrWhiteSpace(squadSnapshot.Description) ? existing.Description : squadSnapshot.Description!;
            var remoteHasTimestamp = squadSnapshot.UpdatedAt != default;
            var nextUpdatedAt = remoteHasTimestamp
                ? squadSnapshot.UpdatedAt
                : existing.UpdatedAt;
            if (remoteHasTimestamp && existing.UpdatedAt != default && nextUpdatedAt < existing.UpdatedAt)
            {
                continue;
            }

            var nextEmblemPath = SaveNetworkSquadEmblem(snapshot, squadSnapshot);
            if (nextEmblemPath is null && !string.IsNullOrWhiteSpace(squadSnapshot.EmblemImageData))
            {
                nextEmblemPath = existing.EmblemPath;
            }
            if (existing.Id != nextId ||
                existing.Commander != nextCommander ||
                existing.Mission != nextMission ||
                existing.RallyPoint != nextRallyPoint ||
                existing.Type != nextType ||
                existing.Description != nextDescription ||
                existing.EmblemPath != nextEmblemPath ||
                existing.UpdatedAt != nextUpdatedAt)
            {
                existing.Id = nextId;
                existing.Commander = nextCommander;
                existing.Mission = nextMission;
                existing.RallyPoint = nextRallyPoint;
                existing.Type = nextType;
                existing.Description = nextDescription;
                existing.EmblemPath = nextEmblemPath;
                existing.UpdatedAt = nextUpdatedAt;
                existing.RefreshComputed();
                changed = true;
            }
        }

        if (changed)
        {
            RenderSquads();
            RenderMySquad();
            RefreshOverlayWindow();
            SaveCurrentConfig();
        }
    }

    private void MarkLocalSquadEdit(SquadRow squad)
    {
        if (string.IsNullOrWhiteSpace(squad.Name))
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        squad.UpdatedAt = now;
        _localSquadEditTimes[squad.Name.Trim()] = now;
    }

    private bool ShouldPreserveLocalSquad(SquadRow existing, NetworkSquadSnapshot remote)
    {
        if (!HasRecentLocalSquadEdit(existing.Name))
        {
            return false;
        }

        if (remote.UpdatedAt == default || existing.UpdatedAt >= remote.UpdatedAt)
        {
            return true;
        }

        _localSquadEditTimes.Remove(existing.Name.Trim());
        return false;
    }

    private bool HasRecentLocalSquadEdit(string? squadName)
    {
        if (string.IsNullOrWhiteSpace(squadName) ||
            !_localSquadEditTimes.TryGetValue(squadName.Trim(), out var editedAt))
        {
            return false;
        }

        if (DateTimeOffset.UtcNow - editedAt <= LocalSquadEditProtectionWindow)
        {
            return true;
        }

        _localSquadEditTimes.Remove(squadName.Trim());
        return false;
    }

    private void MarkLocalFleetLogoEdit()
    {
        _localFleetLogoEditTime = DateTimeOffset.UtcNow;
    }

    private void MarkLocalFleetBannerEdit()
    {
        _localFleetBannerEditTime = DateTimeOffset.UtcNow;
    }

    private bool ShouldPreserveLocalFleetLogo(NetworkFleetSnapshot snapshot)
    {
        if (_localFleetLogoEditTime == default)
        {
            return false;
        }

        if (DateTimeOffset.UtcNow - _localFleetLogoEditTime > LocalSquadEditProtectionWindow)
        {
            _localFleetLogoEditTime = default;
            return false;
        }

        if (snapshot.LastUpdated == default || snapshot.LastUpdated <= _localFleetLogoEditTime)
        {
            return true;
        }

        _localFleetLogoEditTime = default;
        return false;
    }

    private bool ShouldPreserveLocalFleetBanner(NetworkFleetSnapshot snapshot)
    {
        if (_localFleetBannerEditTime == default)
        {
            return false;
        }

        if (DateTimeOffset.UtcNow - _localFleetBannerEditTime > LocalSquadEditProtectionWindow)
        {
            _localFleetBannerEditTime = default;
            return false;
        }

        if (snapshot.LastUpdated == default || snapshot.LastUpdated <= _localFleetBannerEditTime)
        {
            return true;
        }

        _localFleetBannerEditTime = default;
        return false;
    }

    private void ApplyNetworkFleetLogo(NetworkFleetSnapshot snapshot)
    {
        if (ShouldPreserveLocalFleetLogo(snapshot))
        {
            return;
        }

        if (!string.IsNullOrWhiteSpace(snapshot.LogoImageData))
        {
            _fleetLogoPath = SaveNetworkFleetLogo(snapshot);
        }
    }

    private void ApplyNetworkFleetBanner(NetworkFleetSnapshot snapshot)
    {
        return;
    }
}
