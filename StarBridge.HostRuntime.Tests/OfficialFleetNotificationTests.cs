using System.Net;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class OfficialFleetNotificationTests
{
    internal static async Task Run()
    {
        using var handler = new Handler();
        using var client = new CommunityClient(new("https://relay.example.test/"), handler, handler.Clock);
        var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"),
            new("http://127.0.0.1:18080/"), new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api", "organizations.read", "/oauth/callback");
        var session = new ScmOAuthSession("fixture-scm", "fixture-owner", "Pilot", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["organizations.read"]);
        using var host = new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options),
            new ScmProfileCacheStore(Path.GetTempPath()), "fixture", () => null,
            initialSession: session, initialGeneration: 1, communities: client);
        var feed = await ((ICommunityNotificationReader)host).ReadNotificationsAsync(host.CurrentContext!, 1, default);
        Check(feed.Sources.Length == 1, "actual selected SCM notification reader must include its authorized official source without a community or mounted page");
        Check(handler.Requests.All(request => request.Method == HttpMethod.Get), "notification read never sends or marks read");
        var source = feed.Sources.Single();
        Check(source.SourceKind == OrganizationNotificationSourceKind.OfficialFleet && source.JoinedAt is null &&
            !source.ManagementAvailable && source.Tasks.Length == 0 && source.Chat?.Callsign == "", "official notification source does not fabricate join/management or expose archived author identity");
        var root = Path.Combine(Path.GetTempPath(), "official-notice-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            var sink = new Sink();
            using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1, () => true,
                desktop: sink, activationEvent: (g, payload) => BridgeEnvelope.Event("notificationSettings.activated", g, 1, payload));
            var saved = (await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", "fixture-channels", 1,
                new { schemaVersion = 1, expectedRevision = 0, inAppEnabled = true, windowsEnabled = true, position = "bottomRight", preview = "fullContent" }))).Response;
            Check(saved.Status == "ok", "isolated fixture channels configured without a native output");
            var pending = new List<int>();
            using var runtime = new CommunityNotificationRuntime(host, () => (host.CurrentContext, host.Generation), settings.PresentCommunityAsync, handler.Clock,
                pendingManagement: (_, count) => pending.Add(count));
            await runtime.TickAsync();
            Check(sink.Notices.Count == 0, "existing official history starts at a quiet baseline");
            handler.Clock.Now = handler.Clock.Now.AddSeconds(1); handler.Sequence++;
            await runtime.TickAsync();
            Check(sink.Notices.Count == 1 && sink.Notices[0].Community is { Callsign: "", Text: "Incoming fixture" },
                "real selected Host reader feeds its fresh official message through the sole runtime and preview gates");
            var notice = sink.Notices.Single();
            notice.Activated!();
            var activation = (await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.consumeActivation", "fixture-activation", 1,
                new { schemaVersion = 1, activationId = notice.Id.ToString("N") }))).Response;
            Check(activation.Payload.GetProperty("destination").GetString() == "officialFleet", "official notification activation must route to fleet, not the community directory");
            settings.SavePolicies(host.CurrentContext!, 0, Guid.NewGuid().ToString("N"), [new(source.PolicyKey, NotificationSourceMode.DoNotDisturb)], () => true);
            Check(!notice.IsCurrent(), "source mode change retires the old official card");
            async Task Tick(bool newMessage = true) {
                handler.Clock.Now = handler.Clock.Now.AddSeconds(1);
                if (newMessage) handler.Sequence++;
                await runtime.TickAsync();
            }
            await Tick(); Check(sink.Notices.Count == 1, "official DND uses the same source policy gate");
            settings.SavePolicies(host.CurrentContext!, 1, Guid.NewGuid().ToString("N"), [], () => true);
            await Tick(false); Check(sink.Notices.Count == 1, "unmuting never replays the consumed official event");
            handler.Incoming = false; await Tick(); Check(sink.Notices.Count == 1, "own official messages never notify");
            handler.Incoming = true; await Tick(); Check(sink.Notices.Count == 2, "fresh incoming official message after mute can notify");
            async Task Channels(long revision, bool enabled, string preview) {
                var response = (await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", Guid.NewGuid().ToString("N"), 1,
                    new { schemaVersion = 1, expectedRevision = revision, inAppEnabled = true, windowsEnabled = enabled, position = "bottomRight", preview }))).Response;
                Check(response.Status == "ok", "isolated channel fixture saves");
            }
            await Channels(1, false, "sourceOnly");
            await Tick(); Check(sink.Notices.Count == 2, "Windows disabled gate applies to official delivery");
            await Channels(2, true, "hiddenDetails");
            await Tick(false); Check(sink.Notices.Count == 2, "enabling output never replays previously suppressed official message");
            await Tick(); Check(sink.Notices.Count == 3 && sink.Notices.Last().Community is { Name: "", Callsign: "", Text: "", SourceKind: OrganizationNotificationSourceKind.OfficialFleet },
                "hidden details strips official name, author and content before the shared sink");
            handler.Member = false; await Tick();
            Check(sink.Notices.Count == 3 && !sink.Notices.Last().IsCurrent(), "observed membership loss retires old cards and the baseline");
            handler.Member = true; await Tick(); Check(sink.Notices.Count == 3, "membership regrant starts from quiet history");
            await Tick(); Check(sink.Notices.Count == 4, "only a new message after regrant can notify");
            handler.IncludeCommunity = true; handler.OfficialStatus = HttpStatusCode.NotFound;
            await Tick(); Check(sink.Notices.Count == 4, "old Relay missing official endpoint does not replay community history");
            handler.CommunitySequence++; await Tick(false);
            Check(sink.Notices.Count == 5 && sink.Notices.Last().Community?.SourceKind == OrganizationNotificationSourceKind.Community,
                "unavailable official source does not silence the original community notification owner");
            handler.OfficialStatus = HttpStatusCode.OK; await Tick();
            Check(sink.Notices.Count == 5, "official service recovery is a quiet baseline");
            await Tick(); Check(sink.Notices.Count == 6, "official events resume after fresh baseline");
            handler.ChangeAfterMessage = true; await Tick();
            Check(sink.Notices.Count == 6, "source change between last-message and final authorization cannot deliver old scope");
            await Tick(); Check(sink.Notices.Count == 6, "new official source does not inherit old source baseline");
            await Tick(); Check(sink.Notices.Count == 7, "new official source only delivers newly observed content");
            handler.CommunityManagement = true;
            await Tick(false);
            Check(pending.Last() == 1, "the actual community management snapshot owns its pending count");
            handler.CommunityUnavailable = true;
            var independent = await ((ICommunityNotificationReader)host).ReadNotificationsAsync(host.CurrentContext!, 1, default);
            Check(independent.Sources.Length == 1 && independent.Sources[0].SourceKind == OrganizationNotificationSourceKind.OfficialFleet,
                "official read remains independent when the unrelated community feed is unavailable");
            await Tick(false);
            Check(pending.Last() == 1, "an official-only success cannot clear unconfirmed community management work");
            handler.CommunityUnavailable = false;
            handler.CommunityManagement = false;
            await Tick(false);
            Check(pending.Last() == 0, "a confirmed community snapshot can clear completed management work");
            handler.InvalidOfficialSource = true;
            var malformed = await ((ICommunityNotificationReader)host).ReadNotificationsAsync(host.CurrentContext!, 1, default);
            Check(malformed.Sources.Length == 1 && malformed.Sources[0].SourceKind == OrganizationNotificationSourceKind.Community,
                "a malformed official source fails only its own domain without silencing a valid community snapshot");
            handler.InvalidOfficialSource = false;
            Bounds(source, handler.Clock.Now);
            handler.HoldMessage = true;
            using var cancelled = new CancellationTokenSource();
            var read = ((ICommunityNotificationReader)host).ReadNotificationsAsync(host.CurrentContext!, 1, cancelled.Token);
            await handler.MessageStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            cancelled.Cancel();
            var refused = false;
            try { await read; } catch (OperationCanceledException) { refused = true; }
            Check(refused && handler.MessageCancelled, "actual selected notification read propagates cancellation to its held HTTP request");
            handler.HoldMessage = false;
            handler.MessageStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
            handler.ReleaseMessage = new(TaskCreationOptions.RunContinuationsAsynchronously);
            handler.HoldMessage = true;
            var late = runtime.TickAsync();
            await handler.MessageStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            host.Dispose(); handler.ReleaseMessage.TrySetResult();
            await late;
            Check(sink.Notices.Count == 7 && sink.Notices.All(item => !item.IsCurrent()), "disposed account cannot publish a held official snapshot or revive any old card");
        } finally { Directory.Delete(root, true); }
    }
    private static void Bounds(CommunityNotificationSource official, DateTimeOffset now)
    {
        var observer = new CommunityNotificationObserver();
        var communities = Enumerable.Range(0, 64).Select(index => new CommunityNotificationSource("community-" + index, "Community", now.AddDays(-1),
            true, new(1, 1, true, now, now, "", ""), false, [])).ToArray();
        var initial = official with { Chat = official.Chat! with { ServerTime = now, CreatedAt = now } };
        var valid = new CommunityNotificationFeed(now, [.. communities, initial]);
        Check(valid.IsBounded && observer.Observe("owner", 1, valid).Count == 0, "64 communities plus one explicit official source starts quietly");
        var fresh = initial with { Chat = initial.Chat! with { Sequence = initial.Chat!.Sequence + 1, ServerTime = now.AddSeconds(1), CreatedAt = now.AddSeconds(1) } };
        Check(observer.Observe("owner", 1, new(now.AddSeconds(1), [.. communities, fresh])).Count == 1, "65-source bound still admits the actual fresh official event");
        foreach (var invalid in new CommunityNotificationSource[][] {
            [.. communities, communities[0] with { SourceKey = "community-65" }],
            [.. communities.Take(63), initial, initial with { SourceKey = "other-official" }],
            [initial with { SourceKind = (OrganizationNotificationSourceKind)99 }],
            [initial with { ManagementAvailable = true }],
            [initial with { JoinedAt = now.AddDays(-1) }],
        }) {
            var feed = new CommunityNotificationFeed(now.AddSeconds(2), invalid);
            Check(!feed.IsBounded && observer.Observe("owner", 1, feed).Count == 0, "unknown, duplicate-domain, fabricated join and management sources fail closed");
        }
    }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected credential write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected credential deletion");
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal readonly List<HttpRequestMessage> Requests = [];
        internal readonly Clock Clock = new();
        internal long Sequence = 2;
        internal long CommunitySequence = 1;
        internal bool Incoming = true, Member = true, IncludeCommunity, CommunityUnavailable, CommunityManagement, ChangeAfterMessage, HoldMessage, MessageCancelled;
        internal int Fleet = 7;
        internal bool InvalidOfficialSource;
        internal HttpStatusCode OfficialStatus = HttpStatusCode.OK;
        internal TaskCompletionSource MessageStarted = new(TaskCreationOptions.RunContinuationsAsynchronously), ReleaseMessage = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly DateTimeOffset _joined = DateTimeOffset.UtcNow.AddDays(-1);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Requests.Add(request);
            var now = Clock.Now;
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/fleets/notification-sources" && CommunityUnavailable) return new(HttpStatusCode.ServiceUnavailable);
            if (path == "/api/official-fleets/context" && (!Member || OfficialStatus != HttpStatusCode.OK)) return new(Member ? OfficialStatus : HttpStatusCode.Forbidden);
            var code = "OFFICIALFLEET:" + Fleet;
            if (path == "/api/official-fleets/chat/messages") {
                Check(request.RequestUri.Query.Contains("limit=1") && request.RequestUri.Query.Contains("projection=client"), "only existing latest-one client projection is read");
                if (HoldMessage) {
                    MessageStarted.TrySetResult();
                    try { await ReleaseMessage.Task.WaitAsync(token); } catch (OperationCanceledException) { MessageCancelled = true; throw; }
                }
            }
            object body = request.RequestUri!.AbsolutePath switch {
                "/api/fleets/notification-sources" => new { schemaVersion = 1, serverTime = now, sources = IncludeCommunity ? new object[] {
                    new { code = "COMMUNITY", name = "Real community fixture", joinedAt = _joined, managementAvailable = CommunityManagement,
                        tasks = CommunityManagement ? new object[] { new { id = "pending-fixture", createdAt = _joined.AddHours(1) } } : [],
                        chat = new { sequence = CommunitySequence, unread = 1, incoming = true, serverTime = now, createdAt = now, callsign = "Community sender", text = "Community message" } } } : [] },
                "/api/official-fleets/context" => new { schemaVersion = 1, sourceRef = InvalidOfficialSource ? "officialFleet:0" : "officialFleet:" + Fleet, fleetCode = code, name = "Fixture official fleet",
                    chatAvailable = true, announcementsAvailable = true, canSend = false, readReceiptsAvailable = false, canManageAnnouncements = false },
                "/api/official-fleets/chat/channels" => new { totalUnread = 1, channels = new[] { new { channelId = "fleet:" + code, type = "fleet", unreadCount = 1 } } },
                "/api/official-fleets/chat/messages" => new { schemaVersion = 1, channelId = "fleet:" + code, latestSequence = Sequence,
                    oldestSequence = Sequence, hasOlder = true, serverTime = now, canSend = false,
                    messages = new[] { new { sequence = Sequence, isSelf = !Incoming, createdAt = now, senderCallsign = "Unapproved archived identity", text = "Incoming fixture" } } },
                _ => throw new Exception("Unexpected notification route " + request.RequestUri.AbsolutePath)
            };
            if (path == "/api/official-fleets/chat/messages" && ChangeAfterMessage) { ChangeAfterMessage = false; Fleet++; }
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
        }
    }
    private sealed class Clock : TimeProvider {
        internal DateTimeOffset Now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => Now;
        public override long GetTimestamp() => Now.UtcTicks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
    }
    private sealed class Sink : IDesktopNotificationSink {
        internal readonly List<DesktopNotification> Notices = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) { Notices.Add(notice); return ValueTask.FromResult(true); }
        public void Clear() { }
        public void Dispose() { }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
