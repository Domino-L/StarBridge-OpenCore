using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Privacy;

internal static partial class FirstUseBusinessOwnerTests
{
    private sealed class InstallationPublicationTransport : HttpMessageHandler
    {
        internal bool HoldTargets;
        internal readonly TaskCompletionSource Entered = Signal(), Release = Signal();
        internal readonly List<JsonElement> Sent = [];
        internal Action? BeforeClear;
        internal bool FailClear;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var uri = request.RequestUri ?? throw new InvalidOperationException("Synthetic publication URI is required.");
            Check(uri.Host == "publication.example.invalid", "Only injected synthetic publication requests are allowed.");
            if (request.Method == HttpMethod.Get && uri.AbsolutePath == "/api/privacy/community-scopes")
            {
                if (HoldTargets) { Entered.TrySetResult(); await Release.Task; }
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 2, primaryFleetCode = (string?)null, communities = Array.Empty<object>() }) };
            }
            Check(request.Method == HttpMethod.Post && uri.AbsolutePath == "/api/players/realtime-scoped",
                "Scoped publication must never downgrade to a legacy route.");
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            var value = body.RootElement.Clone(); Sent.Add(value);
            if (!value.GetProperty("state").GetProperty("online").GetBoolean()) BeforeClear?.Invoke();
            if (FailClear && !value.GetProperty("state").GetProperty("online").GetBoolean())
                return new(HttpStatusCode.ServiceUnavailable) { Content = new StringContent("Synthetic unavailable withdrawal.") };
            var reply = new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
            reply.Headers.Add("X-StarBridge-Realtime-Version", "3"); return reply;
        }
    }

    private static async Task InstallationPublicationExit()
    {
        foreach (var scenario in new[] { 0, 1, 2, 3 })
        {
            var holdTargets = scenario != 0;
            var backgroundFault = scenario == 2;
            var physicalFault = backgroundFault || scenario == 3;
            using var f = new Fixture(); f.Original.Clock.AllowTimers = true;
            f.Original.Transport.RotateAccessToken = scenario == 1;
            var time = new FirstUseOnlineReturnTests.FrozenSessionTime();
            if (scenario == 1) { f.Original.SessionTime = time; f.Original.Transport.TokenLifetimeSeconds = 2; }
            await f.Start();
            using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
            var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
            var install = prepared.StageInstallation(callbacks, sources)!;
            Check(install.Configure(_ => { }) && install.TryActivate(), "Original installation must activate before publishing.");
            using var transport = new InstallationPublicationTransport();
            f.Original.Host!.ConfigurePrivacyWriter(new PrivacyRelayWriter(new Uri("https://publication.example.invalid/"), transport));
            const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
            var publisher = PrivacyPublicationTestAccess.Ordinary(install.Owner);
            // This auth fixture has no websocket transport. Supply only the
            // external observed server status (Online), retaining the actual
            // visibility store, original owner and real OAuth authority write.
            var visibilityField = typeof(AccountBridgeRuntime).GetField("_presenceVisibility", flags)!;
            ((IDisposable?)visibilityField.GetValue(install.Owner))?.Dispose();
            visibilityField.SetValue(install.Owner, new StarBridge.HostRuntime.Settings.PresenceVisibilityBridge(
                new(f.Original.Local.Root), () => install.Owner.NativeNotificationOwner,
                publisher.ChangeVisibilityAsync, f.Original.Host.SetPresenceVisibilityAuthorityAsync, () => true, () => 1));
            // Exercise the actual presence confirmation rather than injecting a
            // visibility flag or bypassing the account's publication policy.
            f.Original.Transport.AllowPresenceWrite = true;
            var read = await install.DispatchAsync(StarBridge.NativeBridge.BridgeEnvelope.Request("presence.read", Id(),
                install.Owner.Generation, new { schemaVersion = 1 }, f.Original.Host.GameplayTimeContext));
            var presence = await install.DispatchAsync(StarBridge.NativeBridge.BridgeEnvelope.Request("presence.set", Id(),
                install.Owner.Generation, new { schemaVersion = 1, mode = "online",
                    expectedRevision = read.Response.Payload.GetProperty("revision").GetString() }, f.Original.Host.GameplayTimeContext));
            Check(presence.Response.Status == StarBridge.NativeBridge.BridgeResponseStatuses.Ok &&
                presence.Response.Payload.TryGetProperty("state", out var presenceState) && presenceState.GetString() == "ready",
                "Actual original presence authority must confirm Online: " + presence.Response.Status + "/" + presence.Response.Error?.Code +
                $" scenario={scenario} read={read.Response.Status}/{read.Response.Error?.Code} active={install.IsActive} owner={f.Original.Host.GameplayTimeContext is not null} refreshes={f.Original.Transport.TokenRequests}");
            var store = new LocalPrivacyStore(f.Original.Local.Root);
            var owner = f.Original.Host.GameplayTimeContext!;
            var saved = store.Save(owner, 0, Id(), LocalPrivacySettings.EditorDefaults with { Communities = [] }, () => true);
            var applied = await publisher.ApplyAsync(owner, install.Owner.Generation, saved.Revision, default);
            Check(applied.State == "applied" && transport.Sent.Count == 1 &&
                transport.Sent[0].GetProperty("state").GetProperty("online").GetBoolean(),
                "Actual original scoped publication must be acknowledged before retirement: " + applied.State + "/" + applied.ErrorCode + "/sends=" + transport.Sent.Count);
            var policy = Directory.GetFiles(Path.Combine(f.Original.Local.Root, "privacy-local-v1"), "*.json").Single();
            var bytes = File.ReadAllBytes(policy);
            var tokensBeforeTick = f.Original.Transport.TokenRequests;
            if (scenario == 1)
            {
                time.Now += TimeSpan.FromMilliseconds(2200);
                f.Original.Transport.TokenLifetimeSeconds = 3600;
            }
            var publicationGate = (SemaphoreSlim)f.Original.Host.GetType().GetField("_publicationLane", flags)!.GetValue(f.Original.Host)!;
            var gateHeld = !holdTargets;
            if (gateHeld) await publicationGate.WaitAsync();
            transport.HoldTargets = holdTargets;
            transport.BeforeClear = () => Check(f.Original.Vault.LoadActiveAccountKey() is not null,
                "Original credential must remain for actual scoped withdrawal.");
            Task? tick = null;
            try
            {
                tick = publisher.TickAsync();
                if (holdTargets) await Finish(transport.Entered.Task);
                if (scenario == 1) Check(f.Original.Transport.TokenRequests == tokensBeforeTick + 1 && install.IsActive,
                    "Actual rotated OAuth credential must preserve the original installed owner before the held membership read.");
                Check(!tick.IsCompleted, "Positive work must be held at the actual gate or membership read.");
                // Fail the original achievement timer's physical disposal, not
                // a fabricated retirement receipt. Sibling owners must still
                // drain and the original server publication must be withdrawn.
                if (backgroundFault) f.Original.Clock.Created[2].FailDispose = true;
                if (scenario == 3) f.Original.Clock.Created[3].FailDispose = true;
                var exit = install.RetireAsync();
                Check(!exit.IsCompleted && f.Original.Vault.LoadActiveAccountKey() is not null,
                    "Original publisher IO prevents early credential clear.");
                if (gateHeld) { publicationGate.Release(); gateHeld = false; }
                transport.Release.TrySetResult();
                await Finish(tick);
                if (physicalFault)
                {
                    try { await Finish(exit); throw new Exception("Expected original background retirement failure."); }
                    catch (IOException) { }
                }
                else Check(await Finish(exit), "Actual installation retirement must succeed.");
                Check(transport.Sent.Count >= 2 && transport.Sent.Skip(1).All(value =>
                    !value.GetProperty("state").GetProperty("online").GetBoolean() &&
                    value.GetProperty("communities").GetArrayLength() == 0 &&
                    value.GetProperty("state").GetProperty("roomSharedStateFields").GetInt32() == 0),
                    "Late positive work is rejected while exact scoped empty-audience withdrawal succeeds: scenario=" + scenario);
                var policyRetained = bytes.SequenceEqual(File.ReadAllBytes(policy));
                var vaultRetained = f.Original.Vault.LoadActiveAccountKey() is not null;
                var cancelState = (await f.Original.Cancel()).State;
                var timersExited = f.Original.Clock.Created.All(timer => timer.Disposed);
                Check(policyRetained && vaultRetained == physicalFault &&
                    cancelState == (physicalFault ? "recoveryRequired" : "local") && timersExited,
                    $"Withdrawal keeps saved consent and scopes intact; a physical fault retains credentials and recovery state. scenario={scenario}, policy={policyRetained}, vault={vaultRetained}, cancel={cancelState}, timers={timersExited}");
            }
            finally
            {
                if (gateHeld) publicationGate.Release(); transport.Release.TrySetResult();
                if (tick is not null) await Finish(tick);
            }
        }
    }
}

