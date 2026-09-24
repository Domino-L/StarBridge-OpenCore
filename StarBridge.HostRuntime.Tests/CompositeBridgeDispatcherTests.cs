using StarBridge.HostRuntime;
using StarBridge.NativeBridge;

internal static class CompositeBridgeDispatcherTests
{
    internal static async Task ObservesDirectMessages()
    {
        using var host = new RecordingDispatcher();
        using var account = new RecordingDispatcher();
        using var preferences = new RecordingDispatcher();
        using var notifications = new StarBridge.HostRuntime.Notifications.NotificationSettingsBridgeDispatcher(
            Path.Combine(Path.GetTempPath(), "notice-routing-" + Guid.NewGuid().ToString("N")), () => 7);
        using var dispatcher = new CompositeBridgeDispatcher(host, account, preferences, notifications: notifications);
        var time = DateTimeOffset.UtcNow;
        var key = new string('a', 64);
        for (var index = 0; index < 3; index++) {
            account.ResponsePayload = new { schemaVersion = 1, serverTime = time.AddSeconds(index), conversations = new[] {
                new { conversationKey = key, latestSequence = index == 0 ? 1 : 2, lastMessageIncoming = true,
                    unreadCount = 1, lastMessageAt = time.AddSeconds(index == 0 ? 0 : 1) }
            } };
            var request = BridgeEnvelope.Request("directMessages.read", Guid.NewGuid().ToString("N"), 7,
                new { schemaVersion = 1 }, new BridgeAccountContext("fixture", "fixture", "fixture"));
            var result = await dispatcher.DispatchAsync(request);
            Require(result.Response.Status == "ok", "Inbox response remains usable after observation.");
            Require(notifications.DirectMessageCandidates.Count == (index == 1 ? 1 : 0),
                "Composed inbox reads establish a quiet baseline, observe new messages once and suppress duplicates.");
        }
        Require(account.Requests.All(request => request.Name == "directMessages.read") && account.Requests.Count == 3,
            "Observation never submits read receipts or adds network commands.");
    }
    internal static async Task RoutesCommunityRequests()
    {
        using var host = new RecordingDispatcher();
        using var account = new RecordingDispatcher();
        using var preferences = new RecordingDispatcher();
        using var dispatcher = new CompositeBridgeDispatcher(host, account, preferences);
        var context = new BridgeAccountContext("test", "test", "owner");
        foreach (var name in new[] { "communities.read", "communities.execute", "communities.creationOptions", "communities.create", "communities.pickLogo", "communities.cropLogo", "communities.clearLogo", "communities.workspace", "communities.logs", "communities.deleteLog", "communities.disbandPreview", "communities.disband", "communities.chat", "communities.chatDetail", "communities.markChatRead", "communities.sendChat", "communities.media", "communities.profile", "communities.saveProfile", "communities.previewInvite", "communities.acceptInvite", "communities.admissions", "communities.manageAdmissions", "communities.roles", "communities.saveRoles", "communities.memberRole", "communities.saveMemberRole", "communities.memberRemoval", "communities.removeMember", "communities.ownershipTransfer", "communities.transferOwnership", "communities.ownershipExit", "communities.leaveWithSuccessor" })
        {
            var request = BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 2, new { schemaVersion = 1 }, context);
            var response = await dispatcher.DispatchAsync(request);
            Require(response.Response.Status == BridgeResponseStatuses.Ok, $"{name} must reach the account owner");
            Require(ReferenceEquals(account.Requests.Last(), request), "Organization payload and identity preserved.");
        }
        foreach (var name in new[] { "communities.announcements", "communities.announcementDetail", "communities.manageAnnouncements", "communities.ships", "communities.shipImage", "communities.reportShipImage", "communities.hangarSharing", "communities.saveHangarSharing" })
        {
            var request = BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 2, new { schemaVersion = 1 }, context);
            var response = await dispatcher.DispatchAsync(request);
            Require(response.Response.Status == BridgeResponseStatuses.Ok && ReferenceEquals(account.Requests.Last(), request),
                "Announcement request and scoped identity reach the account owner.");
        }
        Require(host.Requests.Count == 0 && preferences.Requests.Count == 0, "Organization request never becomes a local preference write.");
    }
    // Use the exact names emitted by the Flutter profile adapter. Direct OAuth
    // tests cannot detect a missing route in NativeHost/Program's composition.
    internal static async Task RoutesPersonalProfileRequests()
    {
        using var host = new RecordingDispatcher();
        using var account = new RecordingDispatcher();
        using var preferences = new RecordingDispatcher();
        using var dispatcher = new CompositeBridgeDispatcher(host, account, preferences);
        using var cancellation = new CancellationTokenSource();
        var context = new BridgeAccountContext("development", "scm-development", "synthetic");
        foreach (var name in new[] { "personalProfile.getSelf", "personalProfile.updateSelf",
                     "personalProfile.migrationStatus", "personalProfile.migrationPreview", "personalProfile.migrationConfirm",
                     "gameplayTime.read", "gameplayTime.setConsent", "gameplayTime.retry", "gameplayTime.setVisibility",
                     "gameplayTime.historyStatus", "gameplayTime.historyPreview", "gameplayTime.historyConfirm",
                     "privacy.localRead", "privacy.localSave", "personalProfile.localRead", "personalProfile.localSave",
                     "eventSharing.read", "eventSharing.save", "friendSharing.read", "friendSharing.save",
                     "gameIdVisibility.read", "gameIdVisibility.save", "friendRequests.privacyRead", "friendRequests.privacyWrite",
                     "recentlyPlayed.privacyRead", "recentlyPlayed.privacyWrite",
                     "presence.read", "presence.set",
                     "accountSafety.read", "accountSafety.appeal", "friends.read", "friends.execute", "directMessages.read", "directMessages.send", "directMessages.markRead" })
        {
            var request = BridgeEnvelope.Request(
                name, Guid.NewGuid().ToString("N"), 7,
                new { schemaVersion = 1 }, context);
            var response = await dispatcher.DispatchAsync(request, cancellation.Token);
            Require(response.Response.Status == BridgeResponseStatuses.Ok,
                $"{name} must reach the account owner, got {response.Response.Error?.Code}");
            Require(ReferenceEquals(request, account.Requests.Last()),
                "Routing must preserve account context, generation and payload.");
            Require(account.LastToken == cancellation.Token, "Cancellation must be forwarded.");
        }
        Require(account.Requests.Count == 35, "All profile, social, gameplay, presence and privacy requests must reach account dispatch.");
        foreach (var name in new[] { "notificationInbox.read", "notificationInbox.markRead" }) {
            var request = BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 7, new { schemaVersion = 1 }, context);
            var response = await dispatcher.DispatchAsync(request, cancellation.Token);
            Require(response.Response.Status == BridgeResponseStatuses.Ok && ReferenceEquals(request, account.Requests.Last()),
                "Inbox request must preserve the authenticated account context.");
        }
        Require(host.Requests.Count == 0 && preferences.Requests.Count == 0,
            "Profile requests must not reach lifecycle or settings dispatch.");
    }

    internal static async Task PreservesOtherRoutes()
    {
        using var host = new RecordingDispatcher();
        using var account = new RecordingDispatcher();
        using var preferences = new RecordingDispatcher();
        using var dispatcher = new CompositeBridgeDispatcher(host, account, preferences);
        foreach (var name in new[] {
                     "host.hello", "account.getCurrent", "profile.getSelf",
                     "officialFleet.getCurrent", "gameIdentity.getPolicy",
                     "applicationPreferences.get", "applicationPreferences.update" })
        {
            var result = await dispatcher.DispatchAsync(
                BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 0));
            Require(result.Response.Status == BridgeResponseStatuses.Ok, $"Known route {name}");
        }
        var unknown = await dispatcher.DispatchAsync(
            BridgeEnvelope.Request("unregistered.get", "unknown-route", 0));
        Require(unknown.Response.Error?.Code == BridgeErrorCodes.CapabilityUnavailable,
            "Unknown capabilities must remain fail-closed.");
        Require(host.Requests.Count == 1, "Lifecycle route preserved.");
        Require(account.Requests.Count == 4, "Account routes preserved.");
        Require(preferences.Requests.Count == 2, "Settings routes preserved.");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private sealed class RecordingDispatcher : IBridgeRequestDispatcher
    {
        internal object? ResponsePayload;
        internal List<BridgeEnvelope> Requests { get; } = [];
        internal CancellationToken LastToken { get; private set; }
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

        public ValueTask<BridgeDispatchBatch> DispatchAsync(
            BridgeEnvelope request, CancellationToken cancellationToken = default)
        {
            Requests.Add(request);
            LastToken = cancellationToken;
            return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request, ResponsePayload), []));
        }

        public void Dispose() { }
    }
}
