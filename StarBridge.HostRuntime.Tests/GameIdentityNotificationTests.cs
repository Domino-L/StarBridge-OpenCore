using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime;
using StarBridge.NativeBridge;

internal static class GameIdentityNotificationTests
{
    private sealed class UnexpectedDispatcher : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
            => throw new InvalidOperationException("Identity notification escaped the composite notification route");
        public void Dispose() { }
    }
    private sealed class Sink : IDesktopNotificationSink
    {
        internal readonly List<DesktopNotification> Seen = [];
        internal string Reason = "submitted";
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token)
        { Seen.Add(notice); return ValueTask.FromResult(Reason == "submitted"); }
        public ValueTask<DesktopNotificationResult> TryPresentDetailedAsync(DesktopNotification notice, CancellationToken token)
        { Seen.Add(notice); return ValueTask.FromResult(new DesktopNotificationResult(Reason == "submitted", Reason)); }
        public void Clear() { }
        public void Dispose() { }
    }

    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-identity-notice-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            long generation = 1, sequence = 0;
            var owner = new BridgeAccountContext("test", "scm", "synthetic-one");
            var policy = new GameIdentityNotificationPolicy("mismatch", "Pilot_A", "Pilot_B");
            var foreground = false;
            Task<GameIdentityNotificationPolicy>? pendingPolicy = null;
            var sink = new Sink();
            var events = new List<BridgeEnvelope>();
            using var settings = new NotificationSettingsBridgeDispatcher(root, () => generation,
                desktop: sink,
                activationEvent: (g, value) => BridgeEnvelope.Event("notificationSettings.activated", g, ++sequence, value),
                gameIdentityPolicy: (context, token) =>
                {
                    if (context != owner) throw new InvalidOperationException("Synthetic wrong owner");
                    token.ThrowIfCancellationRequested();
                    return pendingPolicy ?? Task.FromResult(policy);
                }, canNotifyGameIdentity: () => !foreground,
                isGameIdentityCurrent: (context, expected) => context == owner && expected.State == policy.State &&
                    string.Equals(expected.AuthoritativeHandle?.Trim(), policy.AuthoritativeHandle?.Trim(), StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(expected.DetectedHandle?.Trim(), policy.DetectedHandle?.Trim(), StringComparison.OrdinalIgnoreCase));
            using var dispatcher = new CompositeBridgeDispatcher(new UnexpectedDispatcher(), new UnexpectedDispatcher(),
                new UnexpectedDispatcher(), notifications: settings);
            dispatcher.EventReady += events.Add;
            async Task<BridgeEnvelope> Call(string name, object body, bool account = true) =>
                (await dispatcher.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), generation,
                    body, account ? owner : null))).Response;
            var schema = new { schemaVersion = 1 };
            var saved = await Call("notificationSettings.save", new
            {
                schemaVersion = 1, expectedRevision = 0, inAppEnabled = true,
                windowsEnabled = true, position = "bottomRight", preview = "sourceOnly"
            }, account: false);
            Check(saved.Status == "ok", "Synthetic notification preference fixture failed");
            var response = await Call("gameIdentity.notifyMismatch", schema);
            Check(response.Status == "ok" && response.Payload.TryGetProperty("submitted", out var submitted) && submitted.GetBoolean(),
                "Host-owned mismatch must reach the real notification dispatcher and fake desktop sink");
            Check(sink.Seen.Count == 1, "First mismatch must submit exactly once");
            Check(response.AccountContext == owner &&
                response.Payload.TryGetProperty("authoritativeHandle", out var actualExpected) && actualExpected.GetString() == "Pilot_A" &&
                response.Payload.TryGetProperty("detectedHandle", out var actualDetected) && actualDetected.GetString() == "Pilot_B",
                "A successful scoped receipt must identify the actual Host policy submitted to the desktop sink");
            var first = sink.Seen[0];
            Check(first.GameIdentityMismatch, "Only the typed identity notification may use its policy");
            Check(first.DirectMessage is null && first.Community is null && first.Activity is null,
                "Identity issue is not a social or player-activity notification");
            Check(first.Activated is not null, "Identity notice must use the existing activation route");
            Check(DesktopNotificationVisibility.SuppressionReason(first, "running", false) == "",
                "Known running game alone does not suppress a typed identity warning");
            Check(DesktopNotificationVisibility.SuppressionReason(first, "unknown", false) == "game-active-or-unknown" &&
                DesktopNotificationVisibility.SuppressionReason(first, "running", true) == "main-window-active-or-unknown" &&
                DesktopNotificationVisibility.SuppressionReason(first, "running", null) == "main-window-active-or-unknown",
                "Unknown game/foreground states remain fail-closed for identity notifications");
            Check(DesktopNotificationVisibility.SuppressionReason(first with { GameIdentityMismatch = false }, "running", false) == "",
                "Background game alone must not suppress ordinary cards after native foreground checks");
            response = await Call("gameIdentity.notifyMismatch", schema);
            Check(!response.Payload.GetProperty("submitted").GetBoolean() && sink.Seen.Count == 1,
                "Repeated policy reads must not repeat the same mismatch");
            Check((!response.Payload.TryGetProperty("authoritativeHandle", out actualExpected) || actualExpected.ValueKind == System.Text.Json.JsonValueKind.Null) &&
                (!response.Payload.TryGetProperty("detectedHandle", out actualDetected) || actualDetected.ValueKind == System.Text.Json.JsonValueKind.Null),
                "A non-submitted response must not claim a delivered identity pair");
            policy = new("mismatch", " pilot_a ", "PILOT_B");
            await Call("gameIdentity.notifyMismatch", schema);
            Check(sink.Seen.Count == 1, "Handle casing and surrounding space must not defeat deduplication");
            Check((await Call("gameIdentity.notifyMismatch", new { schemaVersion = 1, title = "injected" })).Status == "error",
                "Client-supplied presentation text must be rejected");
            Check((await Call("gameIdentity.notifyMismatch", schema, account: false)).Status == "error",
                "An unscoped client request cannot request an identity notification");
            var forged = await dispatcher.DispatchAsync(BridgeEnvelope.Request("gameIdentity.notifyMismatch", "forged", generation,
                schema, new("test", "scm", "other")));
            Check(forged.Response.Status == "error" && sink.Seen.Count == 1,
                "A wrong account cannot borrow the current policy");

            first.Activated!(); first.Activated!();
            Check(events.Count == 1, "The same native identity click must publish at most once");
            Check(!events[0].Payload.GetRawText().Contains("Pilot", StringComparison.OrdinalIgnoreCase),
                "Activation events must not contain handle values");
            var click = new { schemaVersion = 1, activationId = events[0].Payload.GetProperty("activationId").GetString() };
            response = await Call("notificationSettings.consumeActivation", click, account: false);
            Check(response.Payload.GetProperty("destination").GetString() == "gameIdentity",
                "Identity activation must return only its typed destination");
            response = await Call("notificationSettings.consumeActivation", click, account: false);
            Check(!response.Payload.TryGetProperty("destination", out var destination) || destination.ValueKind == System.Text.Json.JsonValueKind.Null,
                "An identity activation cannot be consumed twice");

            policy = new("mismatch", "Pilot_A", "Pilot_C");
            await Call("gameIdentity.notifyMismatch", schema);
            Check(sink.Seen.Count == 2 && !first.IsCurrent(), "A new mismatch replaces only the prior identity issue");
            var recovered = sink.Seen[^1];
            recovered.Activated!();
            var recoveryClick = new { schemaVersion = 1, activationId = events[^1].Payload.GetProperty("activationId").GetString() };
            policy = new("match", "Pilot_A", "Pilot_A");
            Check(!recovered.IsCurrent(),
                "A recovered Host policy must invalidate its queued identity card immediately without another notification request");
            response = await Call("notificationSettings.consumeActivation", recoveryClick, account: false);
            Check(!response.Payload.TryGetProperty("destination", out destination) || destination.ValueKind == System.Text.Json.JsonValueKind.Null,
                "Activation must re-read Host policy and reject an issue that already recovered");
            await Call("gameIdentity.notifyMismatch", schema);
            Check(!recovered.IsCurrent() && sink.Seen.Count == 2, "Recovery withdraws an old identity card without adding a card");

            foreground = true;
            policy = new("mismatch", "Pilot_A", "Pilot_D");
            await Call("gameIdentity.notifyMismatch", schema);
            Check(sink.Seen.Count == 2, "Foreground mismatch is owned by Flutter confirmation, not a desktop card");
            foreground = false;
            await Call("gameIdentity.notifyMismatch", schema);
            Check(sink.Seen.Count == 2, "Foreground-observed mismatch must not replay just because the app becomes background");
            policy = new("mismatch", "Pilot_A", "Pilot_E");
            sink.Reason = "doNotDisturb";
            response = await Call("gameIdentity.notifyMismatch", schema);
            Check(!response.Payload.GetProperty("submitted").GetBoolean() && response.Payload.GetProperty("reason").GetString() == "doNotDisturb",
                "System suppression must be returned without falling back to another channel");
            sink.Reason = "submitted";
            await Call("gameIdentity.notifyMismatch", schema);
            Check(sink.Seen.Count == 3, "Suppressed identity delivery is consumed, not retried");

            await Call("notificationSettings.save", new
            {
                schemaVersion = 1, expectedRevision = 1, inAppEnabled = true,
                windowsEnabled = false, position = "bottomRight", preview = "hiddenDetails"
            }, account: false);
            policy = new("mismatch", "Pilot_A", "Pilot_F");
            response = await Call("gameIdentity.notifyMismatch", schema);
            Check(!response.Payload.GetProperty("submitted").GetBoolean() && sink.Seen.Count == 3,
                "Identity notification must respect the existing Windows notification switch");
            await Call("notificationSettings.save", new
            {
                schemaVersion = 1, expectedRevision = 2, inAppEnabled = true,
                windowsEnabled = true, position = "bottomRight", preview = "hiddenDetails"
            }, account: false);
            await Call("gameIdentity.notifyMismatch", schema);
            Check(sink.Seen.Count == 3, "Enabling the channel must not replay a previously observed mismatch");

            var pending = new TaskCompletionSource<GameIdentityNotificationPolicy>(TaskCreationOptions.RunContinuationsAsynchronously);
            pendingPolicy = pending.Task;
            var oldRead = Call("gameIdentity.notifyMismatch", schema);
            generation++;
            pendingPolicy = null;
            pending.SetResult(new("mismatch", "Pilot_A", "Pilot_G"));
            Check((await oldRead).Status != "ok" && sink.Seen.Count == 3,
                "A policy response arriving after account generation changes must not notify");
            Check(sink.Seen.All(n => !n.IsCurrent()), "Switching accounts invalidates every old identity card");
            policy = new("mismatch", "Pilot_A", "Pilot_B");
            await Call("gameIdentity.notifyMismatch", schema);
            Check(sink.Seen.Count == 4 && sink.Seen[^1].Preview == "hiddenDetails",
                "A new account generation has its own dedupe scope and current privacy preference");

            foreach (var invalid in new[] {
                new GameIdentityNotificationPolicy("unknown", "Pilot_A", "Pilot_X"),
                new GameIdentityNotificationPolicy("mismatch", "Pilot_A", "Pilot_A"),
                new GameIdentityNotificationPolicy("mismatch", "Pilot_A", null),
                new GameIdentityNotificationPolicy("mismatch", "Pilot_A", "bad\nvalue") })
            {
                policy = invalid;
                await Call("gameIdentity.notifyMismatch", schema);
            }
            Check(sink.Seen.Count == 4, "Unknown, equal, incomplete or invalid policies fail closed");
            policy = new("mismatch", "Pilot_A", "Pilot_B");
            await Call("gameIdentity.notifyMismatch", schema);
            Check(sink.Seen.Count == 4 && sink.Seen.All(n => !n.IsCurrent()),
                "An old same-pair card cannot become current again after a later issue/recovery");

            pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
            pendingPolicy = pending.Task;
            oldRead = Call("gameIdentity.notifyMismatch", schema);
            pendingPolicy = null;
            policy = new("mismatch", "Pilot_A", "Pilot_Newer");
            await Call("gameIdentity.notifyMismatch", schema);
            pending.SetResult(new("mismatch", "Pilot_A", "Pilot_Older"));
            Check((await oldRead).Status == "cancelled" && sink.Seen.Count == 5 && sink.Seen[^1].IsCurrent(),
                "A superseded same-account policy read cannot revoke/replace the newer identity issue");
            pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
            pendingPolicy = pending.Task;
            oldRead = Call("gameIdentity.notifyMismatch", schema);
            pendingPolicy = null;
            policy = new("match", "Pilot_A", "Pilot_A");
            pending.SetResult(new("mismatch", "Pilot_A", "Pilot_Expired"));
            var expiredBeforeDisplay = await oldRead;
            Check(expiredBeforeDisplay.Status == "ok" && !expiredBeforeDisplay.Payload.GetProperty("submitted").GetBoolean() &&
                sink.Seen.Count == 5 && sink.Seen.All(n => !n.IsCurrent()),
                "Recovery before first presentation must reject a stale async policy read without entering the native sink");
            pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
            policy = new("mismatch", "Pilot_A", "Pilot_BeforeWait");
            pendingPolicy = pending.Task;
            oldRead = Call("gameIdentity.notifyMismatch", schema);
            pendingPolicy = null;
            policy = new("mismatch", " Pilot_ActualOwner ", " Pilot_ActualDetected ");
            pending.SetResult(policy);
            var actualDelivery = await oldRead;
            Check(actualDelivery.Payload.GetProperty("submitted").GetBoolean() && actualDelivery.AccountContext == owner &&
                actualDelivery.Payload.GetProperty("authoritativeHandle").GetString() == "Pilot_ActualOwner" &&
                actualDelivery.Payload.GetProperty("detectedHandle").GetString() == "Pilot_ActualDetected" && sink.Seen.Count == 6,
                "When policy changes during a read, the receipt must bind the actual delivered pair, not a caller's earlier issue");
            policy = new("mismatch", "Pilot_A", "Pilot_MissingGuard");
            using var missingFreshness = new NotificationSettingsBridgeDispatcher(root, () => generation,
                desktop: sink, gameIdentityPolicy: (_, _) => Task.FromResult(policy), canNotifyGameIdentity: () => true);
            var unavailableFreshness = await missingFreshness.DispatchAsync(BridgeEnvelope.Request("gameIdentity.notifyMismatch", "no-snapshot",
                generation, schema, owner));
            Check(!unavailableFreshness.Response.Payload.GetProperty("submitted").GetBoolean() && sink.Seen.Count == 6,
                "Missing authoritative freshness validation must not submit an identity notification");
            Console.WriteLine("PASS Host identity mismatch notification scope, deduplication, suppression and typed activation");
        }
        finally { Directory.Delete(root, true); }
    }

    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
}
