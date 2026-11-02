using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Identity;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static partial class SharingReviewRegressionTests
{
    internal static async Task M04j()
    {
        var failures = 0;
        foreach (var (name, run) in new (string, Func<Task>)[] {
            ("unconfirmed room pause survives runtime recreation", () => RoomPauseRestart(true)),
            ("disabled room pause survives runtime recreation", () => RoomPauseRestart(false)),
            ("unconfirmed nonmember loop remains read-only", () => NonmemberLoopReadOnly(true)),
            ("disabled nonmember loop remains read-only", () => NonmemberLoopReadOnly(false)),
            ("room keepalive retries admission timeout", RoomAdmissionRetry),
        })
        {
            try { await run(); Console.WriteLine("PASS M04j " + name); }
            catch (Exception error) { failures++; Console.WriteLine("FAIL M04j " + name + ": " + error.Message); }
        }
        Check(failures == 0, "M04j regression failures");
    }

    private sealed class M04jRoom : IDisposable
    {
        internal readonly ScmAccountBridgeHost Host;
        internal readonly AccountBridgeRuntime Runtime;
        internal readonly LocalPrivacyStore Store;
        internal readonly PrivacyPublication Main;
        internal readonly M04jTransport Transport = new();
        private readonly M04fHandler _identity = new();
        private readonly PartyRoomReader _rooms;
        internal BridgeAccountContext Owner => Host.GameplayTimeContext!;
        internal M04jRoom(string root, bool? enabled = null)
        {
            var session = new ScmOAuthSession("fixture-scm", "fixture-subject", "Fixture", "synthetic-only",
                DateTimeOffset.UtcNow.AddMinutes(5), [], GameIdentityHandle: "Fixture",
                GameIdentityStatus: ScmGameIdentityStatus.Verified);
            Host = new(new OAuthPkceClient(new ScmHttpClient(_identity), new NoM04gVault(), ScmOAuthOptions.CreateDefault()),
                new ScmProfileCacheStore(), "fixture", () => null, initialSession: session);
            Store = new(root);
            if (enabled is { } value)
                Store.Save(Owner, 0, Guid.NewGuid().ToString("N"), new(value,
                    new(PlayerSharedStateFields.Presence, false, true, []), new(PlayerSharedStateFields.None, false)), () => true);
            _rooms = new(new Uri("https://sharing.invalid"), Transport);
            typeof(ScmAccountBridgeHost).GetField("_partyRooms", PrivateInstance)!.SetValue(Host, _rooms);
            SetM04gObservation(Host, 1);
            Runtime = new(Host, privacy: Store, visibility: new(root), backgroundTime: new SharingTestClock());
            Main = PrivacyPublicationTestAccess.Ordinary(Runtime);
            typeof(PrivacyPublication).GetField("_send", PrivateInstance)!.SetValue(Main,
                new Func<PrivacyPublicationInput, JsonElement, CancellationToken, Task>((_, body, _) => {
                    Check(!body.GetProperty("online").GetBoolean(), "room actions must never grant telemetry consent");
                    return Task.CompletedTask;
                }));
        }
        internal Task Renew() => (Task)typeof(ScmAccountBridgeHost).GetMethod("RenewRoomMembershipAsync", PrivateInstance)!
            .Invoke(Host, [Owner, Host.Generation, CancellationToken.None])!;
        public void Dispose() { Runtime.Dispose(); Host.Dispose(); _rooms.Dispose(); _identity.Dispose(); }
    }

    private static async Task RoomPauseRestart(bool? enabled)
    {
        var root = Directory.CreateTempSubdirectory("room-pause-restart-").FullName;
        try
        {
            using (var first = new M04jRoom(root, enabled))
            {
                if (enabled is null)
                    Check(first.Store.Read(first.Owner).Revision == 0 &&
                        Directory.GetFiles(root, "*", SearchOption.AllDirectories).Length == 0,
                        "first run must not save a privacy policy before joining");
                Check(!first.Store.HasPublicationConsent(first.Owner), "fixture has no realtime consent");
                await first.Renew();
                Check(first.Transport.Posts == 1, "room keepalive works without realtime consent");
                SetM04gObservation(first.Host, 3);
                await first.Main.TickAsync();
                await first.Renew();
                Check(first.Transport.Posts == 1, "invisible observation blocks room keepalive");
            }
            using (var restarted = new M04jRoom(root))
            {
                SetM04gObservation(restarted.Host, 1);
                await restarted.Main.TickAsync();
                await restarted.Renew();
                await restarted.Renew();
                Check(restarted.Transport.Posts == 0, "recreated runtime cannot renew after ordinary online observation");
                Check(new LocalPrivacyStore(root).IsPublicationPaused(restarted.Owner), "room-only pause must be durable");
                Check(!restarted.Store.HasPublicationConsent(restarted.Owner), "restart cannot grant realtime consent");
                await restarted.Main.ChangeVisibilityAsync(restarted.Owner, restarted.Host.Generation,
                    _ => {
                        // Simulate the confirmed online authority receipt inside
                        // the explicit action, without any real transport.
                        Field<PresenceVisibilityBridge>(restarted.Runtime, "_presenceVisibility")
                            .ConfirmObservedModeForExplicitSharing(restarted.Owner, restarted.Host.Generation);
                        return Task.CompletedTask;
                    }, default);
                Check(!restarted.Store.IsPublicationPaused(restarted.Owner), "explicit online action clears durable pause");
                await restarted.Renew();
                Check(restarted.Transport.Posts == 1 && !restarted.Store.HasPublicationConsent(restarted.Owner),
                    "explicit resume permits room keepalive without enabling realtime sharing");
            }
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task RoomAdmissionRetry()
    {
        var root = Directory.CreateTempSubdirectory("room-admission-retry-").FullName;
        try
        {
            using var f = new M04jRoom(root, false);
            await f.Renew();
            f.Store.PositiveAdmission.WaitTimeout = TimeSpan.FromMilliseconds(60);
            var held = await f.Store.PositiveAdmission.EnterAsync(default);
            try
            {
                f.Host.EnableRoomMembershipKeepalive(TimeSpan.FromMilliseconds(10));
                await WaitM04j(() => Volatile.Read(ref f.Transport.Reads) >= 2);
                await Task.Delay(180); // Hold admission through multiple full timeout/backoff cycles.
                Check(!f.Host.RoomKeepaliveCompletion.IsCompleted, "admission timeout must not exit the background loop");
                Check(f.Transport.Posts == 1, "occupied admission cannot send a renewal");
                held.Dispose();
                await WaitM04j(() => Volatile.Read(ref f.Transport.Posts) > 1);
                Check(!f.Host.RoomKeepaliveCompletion.IsCompleted, "the same background loop resumes after admission release");
            }
            finally
            {
                held.Dispose();
                f.Host.Dispose();
                try { await f.Host.RoomKeepaliveCompletion.WaitAsync(TimeSpan.FromSeconds(3)); }
                catch (Exception) when (f.Host.RoomKeepaliveCompletion.IsFaulted) { /* Asserted above on the unfixed loop. */ }
            }
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task NonmemberLoopReadOnly(bool? enabled)
    {
        var root = Directory.CreateTempSubdirectory("room-nonmember-readonly-").FullName;
        try
        {
            using var f = new M04jRoom(root, enabled);
            f.Transport.Member = false;
            await f.Renew();
            var before = Directory.GetFiles(root, "*", SearchOption.AllDirectories).ToDictionary(p => p, File.ReadAllBytes);
            try
            {
                f.Host.EnableRoomMembershipKeepalive(TimeSpan.FromMilliseconds(10));
                await WaitM04j(() => Volatile.Read(ref f.Transport.Reads) >= 2);
                SetM04gObservation(f.Host, 3);
                await f.Main.TickAsync();
                SetM04gObservation(f.Host, 1);
                await f.Main.TickAsync();
                await f.Renew();
                Check(!f.Store.IsPublicationPaused(f.Owner) && f.Transport.Posts == 0,
                    "an idle directory loop is not room renewal or membership");
                Check(before.Count == Directory.GetFiles(root, "*", SearchOption.AllDirectories).Length &&
                    before.All(pair => pair.Value.SequenceEqual(File.ReadAllBytes(pair.Key))),
                    "nonmember observation must preserve every file count and byte");
            }
            finally { f.Host.Dispose(); await f.Host.RoomKeepaliveCompletion.WaitAsync(TimeSpan.FromSeconds(3)); }
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task WaitM04j(Func<bool> ready)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        while (!ready()) await Task.Delay(5, timeout.Token);
    }

    private sealed class M04jTransport : HttpMessageHandler
    {
        internal int Reads, Posts;
        internal bool Member = true;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            ct.ThrowIfCancellationRequested();
            if (request.Method == HttpMethod.Get)
            {
                Interlocked.Increment(ref Reads);
                var directory = JsonNode.Parse(PartyRoomReaderTests.Wire(Member ? "one" : null, PartyRoomReaderTests.Room("one")))!;
                directory["supportsMembershipKeepalive"] = true;
                directory["viewerMembershipToken"] = Member ? "0123456789abcdef0123456789abcdef" : null;
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(directory.ToJsonString()) });
            }
            Check(request.RequestUri!.AbsolutePath == "/api/party-rooms/keepalive", "only room renewals reach this handler");
            Interlocked.Increment(ref Posts);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NoContent));
        }
    }
}

