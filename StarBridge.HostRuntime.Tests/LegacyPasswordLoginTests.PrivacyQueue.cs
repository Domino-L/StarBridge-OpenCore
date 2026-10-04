using System.Reflection;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task PrivacyQueueTimeoutKeepsConsent()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-privacy-queue-").FullName;
        try
        {
            using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
            using var host = CreateHost(login);
            await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
            var gate = (SemaphoreSlim)typeof(ScmAccountBridgeHost).GetField("_mutationGate", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(host)!;
            var input = new PrivacyPublicationInput(host.CurrentContext!, host.Generation, "Commander_One", true, null, GameLogSessionSnapshot.Empty);
            var store = new LocalPrivacyStore(root);
            store.Save(input.Owner, 0, Guid.NewGuid().ToString("N"), new(true,
                new(PlayerSharedStateFields.Presence, false, true, []), new(PlayerSharedStateFields.None, false)), () => true);
            var blocked = false;
            var onlineWrites = 0;
            var offlineWrites = 0;
            var clock = new SharingTestClock();
            Exception? queueError = null;
            using var publication = new PrivacyPublication(store, () => input, async (current, payload, token) =>
            {
                if (!payload.GetProperty("online").GetBoolean()) { offlineWrites++; return; }
                onlineWrites++;
                if (!blocked) return;
                // Hold the actual shared Host writer gate, not a fabricated
                // exception. Only shorten the publication's internal deadline.
                await gate.WaitAsync();
                try
                {
                    using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
                    var queued = host.PublishPrivacyAsync(current, payload, deadline.Token);
                    deadline.Cancel();
                    try { await queued; }
                    catch (Exception error) { queueError = error; throw; }
                }
                finally { gate.Release(); }
            }, startTimer: false, timeProvider: clock);
            var journal = new PrivacyPublicationJournal(root);
            publication.Diagnostic = journal.Record;
            await publication.ApplyAsync(input.Owner, input.Generation, 1, default);
            var savedPolicy = JsonSerializer.Serialize(store.Read(input.Owner), LocalPrivacyStore.Json);
            var acknowledgedAt = publication.Status.AppliedAt;
            blocked = true;
            await publication.TickAsync();
            Check(queueError is OperationCanceledException, "Actual Host queue must hit the internal cancellation path.");
            Check(publication.Status.State == "reconnecting" && store.HasPublicationConsent(input.Owner) && offlineWrites == 0,
                $"Host queue timeout must retain consent and not publish Offline: state={publication.Status.State}, consent={store.HasPublicationConsent(input.Owner)}, error={queueError!.GetType().Name}, clears={offlineWrites}");
            blocked = false;
            var attemptsAfterTimeout = onlineWrites;
            await publication.TickAsync();
            Check(onlineWrites == attemptsAfterTimeout && publication.Status.State == "reconnecting" &&
                publication.Status.AppliedAt == acknowledgedAt && store.HasPublicationConsent(input.Owner) && offlineWrites == 0 &&
                JsonSerializer.Serialize(store.Read(input.Owner), LocalPrivacyStore.Json) == savedPolicy,
                "An immediate input wake must preserve consent and policy without bypassing retry backoff or inventing a receipt.");
            clock.Advance(4);
            await publication.TickAsync();
            Check(onlineWrites == attemptsAfterTimeout && publication.Status.State == "reconnecting" &&
                publication.Status.AppliedAt == acknowledgedAt && store.HasPublicationConsent(input.Owner) && offlineWrites == 0 &&
                JsonSerializer.Serialize(store.Read(input.Owner), LocalPrivacyStore.Json) == savedPolicy,
                "A heartbeat before the five-second deadline must not resend or change consent and policy.");
            clock.Advance(1);
            await publication.TickAsync();
            Check(onlineWrites == attemptsAfterTimeout + 1 && publication.Status.State == "applied" &&
                publication.Status.AppliedAt == clock.GetUtcNow() && store.HasPublicationConsent(input.Owner) && offlineWrites == 0 &&
                JsonSerializer.Serialize(store.Read(input.Owner), LocalPrivacyStore.Json) == savedPolicy,
                "The heartbeat at the retry deadline recovers without a new apply or policy edit.");
            var diagnostics = File.ReadAllText(Path.Combine(root, "realtime-sharing-diagnostics.log"));
            Check(diagnostics.Contains("state=reconnecting reason=timeout") && !diagnostics.Contains(input.Handle),
                "Local transition evidence contains only bounded states and reasons, no identity.");
            publication.Diagnostic = (_, _) => throw new IOException("Synthetic diagnostic failure");
            blocked = true;
            await publication.TickAsync();
            Check(publication.Status.State == "reconnecting" && store.HasPublicationConsent(input.Owner),
                "Diagnostic failures cannot revoke consent or block recovery.");
        }
        finally { Directory.Delete(root, true); }
    }
}
