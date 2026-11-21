using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class ConsentChoiceChangedTests
{
    private const string Code = "official_fleet.choice_changed";
    private static readonly BridgeAccountContext Owner = new("test", "fixture.invalid", "choice-fixture");
    private static readonly OfficialFleetRealtimeTarget Target = new("fixture", 1, "SYNTHETIC", "scm-observed-membership-row-v1:1");
    private static PrivacyPublicationInput Input => new(Owner, 1, "Fixture", true, "LIVE", GameLogSessionSnapshot.Empty, AppPresenceConfirmed: true);
    private static LocalPrivacySettings Settings => new(true, new(0, false, false, []),
        new(PlayerSharedStateFields.Presence, true), [],
        OfficialFleet: new(Target, PlayerSharedStateFields.Presence, "initial", Guid.NewGuid().ToString("N")));

    internal static async Task Run()
    {
        await Writer();
        await NoRetryAndExplicitSave();
        await SavingWhilePausedOrOffLiftsTheBlock();
        Console.WriteLine("PASS consent PUT 409, diagnostics, lane isolation and explicit revision recovery");
    }

    private static async Task Writer()
    {
        var settings = Settings;
        var remote = new OfficialRealtimeConsentWire("fixture", Target, settings.OfficialFleet!.Fields,
            Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"));
        var puts = 0;
        using var writer = new PrivacyRelayWriter(new Uri("https://fixture.invalid"), new Handler(request => {
            if (request.Method == HttpMethod.Get)
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 4, consent = remote }) };
            Check(request.Method == HttpMethod.Put && request.RequestUri!.AbsolutePath.EndsWith("/consent"), "No publish or silent adoption");
            puts++;
            return new(HttpStatusCode.Conflict);
        }));
        try {
            await writer.SendAsync("synthetic", PrivacyPublicationPayload.Build(Input, settings, false), default, allowOfficialPositive: true);
            throw new Exception("Expected consent conflict");
        } catch (AccountBridgeHostException e) {
            Check(e.Code == Code && e.HttpStatus == HttpStatusCode.Conflict, "Consent conflict must preserve choice_changed/409, never identity_required");
        }
        Check(puts == 1, "One PUT; no automatic refresh/save");

        // After the explicit save the real PUT carries the server's current revision and the new operation.
        var confirmed = settings.OfficialFleet with { ExpectedServerRevision = remote.Revision, OperationId = Guid.NewGuid().ToString("N") };
        string? putRevision = null, putOperation = null;
        using var recovered = new PrivacyRelayWriter(new Uri("https://fixture.invalid"), new Handler(request => {
            if (request.Method == HttpMethod.Get)
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 4, consent = remote }) };
            if (request.Method == HttpMethod.Put) {
                using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().Result);
                var choice = body.RootElement.GetProperty("choice");
                putRevision = choice.GetProperty("expectedServerRevision").GetString();
                putOperation = choice.GetProperty("operationId").GetString();
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 4,
                    consent = remote with { Revision = Guid.NewGuid().ToString("N"), OperationId = putOperation! } }) };
            }
            return new(HttpStatusCode.ServiceUnavailable); // Stop at publish; only the PUT matters here.
        }));
        try {
            await recovered.SendAsync("synthetic", PrivacyPublicationPayload.Build(Input, settings with { OfficialFleet = confirmed }, false),
                default, allowOfficialPositive: true);
        } catch (AccountBridgeHostException e) when (e.Code != Code) { }
        Check(putRevision == remote.Revision && putOperation == confirmed.OperationId, "Recovered PUT body carries the server revision and the new operation");
    }

    private static async Task NoRetryAndExplicitSave()
    {
        var root = Directory.CreateTempSubdirectory("sb-choice-changed-").FullName;
        try {
            var store = new LocalPrivacyStore(root);
            var clock = new SharingTestClock();
            var settings = Settings;
            store.Save(Owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
            // The relay accepts a positive main fleet choice only at its current revision.
            var serverRevision = Guid.NewGuid().ToString("N");
            var official = 0; var ordinary = 0; var ordinaryForbidden = false;
            using var pair = new PrivacyPublicationPair(store, () => Input, (_, body, _) => {
                if (body.TryGetProperty("officialFleet", out var choice)) {
                    official++;
                    if (body.GetProperty("online").GetBoolean() &&
                        choice.GetProperty("expectedServerRevision").GetString() != serverRevision)
                        throw new AccountBridgeHostException(Code, httpStatus: HttpStatusCode.Conflict);
                } else if (body.GetProperty("online").GetBoolean()) {
                    ordinary++;
                    if (ordinaryForbidden)
                        throw new AccountBridgeHostException("privacy_publication.forbidden", httpStatus: HttpStatusCode.Forbidden);
                }
                return Task.CompletedTask;
            }, startTimer: false, timeProvider: clock);
            pair.Diagnostic = new PrivacyPublicationJournal(root).Record;
            await pair.ApplyAsync(Owner, 1, 1, default);
            Check(pair.OfficialStatus.State == "failed" && pair.Status.ErrorCode == Code && pair.Status.State == "failed", "Merged status retains official failure");
            Check(pair.OrdinaryStatus.State == "applied" && ordinary > 0, "Ordinary sharing continues");
            var before = official;
            foreach (var seconds in new[] { 5, 60, 300, 900, 86400 }) {
                clock.Advance(seconds); await pair.TickAsync();
                Check(official == before, "Same choice has no short or long retry");
                Check(pair.Status.State != "identityRequired" && pair.Status.ErrorCode == Code, "No identity misclassification");
            }
            Check(File.ReadAllText(Path.Combine(root, "realtime-sharing-diagnostics.log")).Contains("reason=officialChoiceChanged"), "Safe diagnostic reason");
            // A community-only save applies both lanes but carries the same main fleet operation: it stays blocked.
            var saved = store.Read(Owner);
            store.Save(Owner, saved.Revision, Guid.NewGuid().ToString("N"),
                saved.Settings! with { Room = new(PlayerSharedStateFields.Presence | PlayerSharedStateFields.Location, true) }, () => true);
            await pair.ApplyAsync(Owner, 1, store.Read(Owner).Revision, default, preservePause: true);
            Check(official == before, "A community save never replays the refused main fleet operation");
            Check(pair.OfficialStatus.State == "failed" && pair.Status.ErrorCode == Code, "The block survives an unrelated save");
            // The ordinary lane failing at the same time must not hide the reconfirmation.
            ordinaryForbidden = true;
            clock.Advance(60); await pair.TickAsync();
            await pair.ApplyAsync(Owner, 1, store.Read(Owner).Revision, default, preservePause: true);
            Check(pair.OrdinaryStatus.ErrorCode is not null, "Fixture: ordinary lane is failing");
            Check(pair.Status.ErrorCode == Code, "The merged status still asks for the main fleet reconfirmation");
            Check(official == before, "Still no replay");
            ordinaryForbidden = false;
            // A Host restart rebuilds the store and both lanes. The refused operation stays
            // blocked until an explicit save; this relay would accept it, so any send would show.
            var restartedStore = new LocalPrivacyStore(root);
            Check(restartedStore.ReadRefusedOfficialOperation(Owner) == settings.OfficialFleet!.OperationId, "The refused operation is persisted");
            var restartedPositive = 0;
            using (var restarted = new PrivacyPublicationPair(restartedStore, () => Input, (_, body, _) => {
                if (body.TryGetProperty("officialFleet", out _) && body.GetProperty("online").GetBoolean()) restartedPositive++;
                return Task.CompletedTask;
            }, startTimer: false, timeProvider: clock)) {
                await restarted.TickAsync();
                await restarted.ApplyAsync(Owner, 1, restartedStore.Read(Owner).Revision, default);
                clock.Advance(900); await restarted.TickAsync();
                Check(restartedPositive == 0, "A restart never resends the refused main fleet operation");
                Check(restarted.OfficialStatus.State == "failed" && restarted.Status.ErrorCode == Code, "After a restart the reconfirmation is still asked for");
            }
            // The ordinary settings save path supplies fresh context revision and a new operation.
            var remoteRevision = serverRevision;
            var bridge = new OfficialFleetRealtimePrivacyBridge(store, () => (Owner, 1L), (_, _, _) =>
                Task.FromResult(new OfficialRealtimeContextWire(4, "officialFleet:1", Target, null, remoteRevision, true)), () => true);
            var read = await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetRead", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1 }, Owner), default);
            var operation = Guid.NewGuid().ToString("N");
            var save = await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetSave", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1, contextRef = read.Response.Payload.GetProperty("contextRef").GetString(), expectedRevision = store.Read(Owner).Revision,
                    operationId = operation, fields = (int)settings.OfficialFleet!.Fields }, Owner), default);
            Check(save.Response.Status == "ok", "Normal explicit save succeeds");
            var choice = store.Read(Owner).Settings!.OfficialFleet!;
            Check(choice.ExpectedServerRevision == remoteRevision && choice.OperationId == operation && choice.Target == Target &&
                choice.Fields == settings.OfficialFleet.Fields, "Fresh server version/new operation preserve scope");
            await pair.ApplyAsync(Owner, 1, store.Read(Owner).Revision, default, preservePause: true);
            Check(pair.OfficialStatus.State == "applied" && pair.Status.ErrorCode is null && official > before, "Explicit save resumes publication");
            Check(RefusedMarkers(root) == 0, "The explicit save deletes the persisted block file");
            // A rebuilt Host after that save publishes the new choice.
            var rebuiltStore = new LocalPrivacyStore(root);
            var rebuiltPositive = 0;
            using (var rebuilt = new PrivacyPublicationPair(rebuiltStore, () => Input, (_, body, _) => {
                if (body.TryGetProperty("officialFleet", out _) && body.GetProperty("online").GetBoolean()) rebuiltPositive++;
                return Task.CompletedTask;
            }, startTimer: false, timeProvider: clock)) {
                await rebuilt.ApplyAsync(Owner, 1, rebuiltStore.Read(Owner).Revision, default);
                Check(rebuiltPositive > 0 && rebuilt.OfficialStatus.State == "applied", "A rebuilt Host publishes the newly saved choice");
            }
        } finally { Directory.Delete(root, true); }
    }

    private static int RefusedMarkers(string root)
    {
        var directory = Path.Combine(root, "privacy-local-v1");
        return Directory.Exists(directory) ? Directory.GetFiles(directory, "*.official-refused").Length : 0;
    }

    // The persisted block is lifted by any save of a different main fleet choice, even while
    // sharing is paused or off (no publication runs then). A save of the same choice keeps it.
    private static Task SavingWhilePausedOrOffLiftsTheBlock()
    {
        var root = Directory.CreateTempSubdirectory("sb-choice-marker-").FullName;
        try {
            var store = new LocalPrivacyStore(root);
            var settings = Settings;
            var refused = settings.OfficialFleet!.OperationId;
            store.Save(Owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
            store.SetRefusedOfficialOperation(Owner, refused);
            Check(RefusedMarkers(root) == 1, "Fixture: block persisted");
            // Same main fleet choice (an ordinary edit) keeps the block.
            var revision = store.Read(Owner).Revision;
            store.Save(Owner, revision, Guid.NewGuid().ToString("N"),
                settings with { Room = new(PlayerSharedStateFields.Presence | PlayerSharedStateFields.Ship, true) }, () => true);
            Check(store.ReadRefusedOfficialOperation(Owner) == refused, "An ordinary save keeps the block");
            // Paused: a new main fleet choice still lifts it.
            revision = store.Read(Owner).Revision;
            store.SetPublicationPaused(Owner, revision, true, () => true);
            store.Save(Owner, store.Read(Owner).Revision, Guid.NewGuid().ToString("N"),
                store.Read(Owner).Settings! with { OfficialFleet = settings.OfficialFleet with { OperationId = Guid.NewGuid().ToString("N") } }, () => true);
            Check(RefusedMarkers(root) == 0, "A new main fleet save while paused deletes the block file");
            // Sharing off with the main fleet choice removed also lifts it.
            store.SetRefusedOfficialOperation(Owner, store.Read(Owner).Settings!.OfficialFleet!.OperationId);
            store.Save(Owner, store.Read(Owner).Revision, Guid.NewGuid().ToString("N"),
                store.Read(Owner).Settings! with { PublicationEnabled = false, OfficialFleet = null }, () => true);
            Check(RefusedMarkers(root) == 0, "Removing the main fleet choice deletes the block file");
        } finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(respond(request));
    }
}
