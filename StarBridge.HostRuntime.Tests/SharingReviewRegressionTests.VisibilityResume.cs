using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static partial class SharingReviewRegressionTests
{
    // Registered in the ordinary default suite as well as selectable with --filter CX-L11.
    internal static readonly (string Name, Func<Task> Test)[] VisibilityResumeCases = [
        ("CX-L11 online receipt supersedes cached invisible", () => ReceiptResumesCachedInvisible("online", 1)),
        ("CX-L11 in-game receipt supersedes cached invisible", () => ReceiptResumesCachedInvisible("inGame", 2)),
        ("CX-L11 invisible receipt persists pause", InvisibleReceiptPersistsPause),
        ("CX-L11 fresh external invisible still pauses", FreshExternalInvisible),
        ("CX-L11 new invisible during receipt takes precedence", InvisibleDuringReceipt),
        ("CX-L11 disconnect during receipt preserves missing observation", DisconnectDuringReceipt),
        ("CX-L11 repeated null during receipt rejects online observation", () => NullBeforeReceipt(false)),
        ("CX-L11 null invisible null during receipt rejects online observation", () => NullBeforeReceipt(true)),
        ("CX-L11 identity pending journal reason", IdentityPendingJournal),
        ("CX-L11 changed generation rejects receipt", () => ChangedReceiptScope(false)),
        ("CX-L11 changed account rejects receipt", () => ChangedReceiptScope(true)),
    ];

    private static async Task ReceiptResumesCachedInvisible(string mode, int status)
    {
        using var f = new VisibilityResumeFixture();
        await f.Start();
        SetM04gObservation(f.Host, 3);
        await f.Publication.TickAsync();
        Check(f.Publication.Status.State == "withdrawn" && f.PausedOnDisk(), "seed durable invisible pause");
        var positives = f.Positives;
        f.Handler.Status = status;
        await f.Set(mode);
        Check(f.Publication.Status.State == "applied" && f.Positives == positives + 1,
            "confirmed " + mode + " must resume sharing despite the unexpired cached 3");
        Check(!f.PausedOnDisk(), "confirmed online must not persist the stale invisible pause");
        Check(f.Bridge.ReadPublicationSnapshot(wakePublication: false).Observation == status,
            "snapshot uses the confirmed server receipt");
        await f.Publication.TickAsync();
        Check(f.Publication.Status.State == "applied" && !f.PausedOnDisk(), "next tick stays resumed");
    }

    private static async Task InvisibleReceiptPersistsPause()
    {
        using var f = new VisibilityResumeFixture();
        await f.Start();
        var positives = f.Positives;
        f.Handler.Status = 3;
        await f.Set("invisible");
        Check(f.Publication.Status.State == "withdrawn" && f.PausedOnDisk(),
            "confirmed invisible must withdraw and persist pause");
        await f.Publication.TickAsync();
        Check(f.Positives == positives && f.Clears > 0, "invisible blocks subsequent positive writes");
    }

    private static async Task FreshExternalInvisible()
    {
        using var f = new VisibilityResumeFixture();
        await f.Start();
        SetM04gObservation(f.Host, 3);
        await f.Publication.TickAsync();
        await f.Set("online");
        Check(f.Publication.Status.State == "applied" && !f.PausedOnDisk(), "explicit online completes first");
        var positives = f.Positives;
        // Same cache seam the realtime callback writes, after the authority call completed.
        SetM04gObservation(f.Host, 3);
        Check(f.Bridge.ReadPublicationSnapshot(wakePublication: false).Observation == 3, "fresh external 3 is observed");
        await f.Publication.TickAsync();
        Check(f.Publication.Status.State == "withdrawn" && f.PausedOnDisk(), "fresh external 3 still persists pause");
        SetM04gObservation(f.Host, 1);
        await f.Publication.TickAsync();
        Check(f.Positives == positives && f.PausedOnDisk(), "later passive online cannot undo external pause");
    }

    private static async Task InvisibleDuringReceipt()
    {
        using var f = new VisibilityResumeFixture();
        await f.Start();
        // Repeated status observations must still advance the receipt fence.
        SetM04gObservation(f.Host, 3);
        await f.Publication.TickAsync();
        var positives = f.Positives;
        f.Handler.BeforeReceipt = () => SetM04gObservation(f.Host, 3);
        await f.Set("online");
        Check(f.Publication.Status.State != "applied", "new invisible during PUT must block sharing");
        Check(f.PausedOnDisk(), "new invisible during PUT must retain durable pause");
        Check(f.Positives == positives, "new invisible during PUT must block positive sends");
        Check(f.Bridge.ReadPublicationSnapshot(wakePublication: false).Observation == 3,
            "online receipt cannot replace the newer invisible observation");
        await f.Publication.TickAsync();
        Check(f.Publication.Status.State != "applied" && f.PausedOnDisk() && f.Positives == positives,
            "next tick must retain the newer invisible pause");
    }

    private static async Task DisconnectDuringReceipt()
    {
        using var f = new VisibilityResumeFixture();
        await f.Start();
        var positives = f.Positives;
        f.Handler.BeforeReceipt = () => SetM04gObservation(f.Host, null);
        await f.Set("online");
        var snapshot = f.Bridge.ReadPublicationSnapshot(wakePublication: false);
        Check(snapshot.Observation is null, "online receipt cannot restore observation after disconnect");
        Check(f.Publication.Status.State == "reconnecting" &&
            snapshot.SuspensionError == "privacy_publication.network_unavailable",
            "disconnect must retain the existing reconnecting suspension");
        Check(!f.PausedOnDisk(), "disconnect alone must not persist an invisible pause");
        Check(f.Positives == positives, "disconnect during PUT must block positive sends");
        await f.Publication.TickAsync();
        Check(f.Bridge.ReadPublicationSnapshot(wakePublication: false).Observation is null &&
            f.Publication.Status.State == "reconnecting" && f.Positives == positives,
            "next tick must remain suspended without new realtime evidence");
    }

    private static async Task NullBeforeReceipt(bool transientInvisible)
    {
        using var f = new VisibilityResumeFixture();
        await f.Start();
        SetM04gObservation(f.Host, null);
        await f.Publication.TickAsync();
        Check(f.Bridge.ReadPublicationSnapshot(wakePublication: false).Observation is null &&
            f.Publication.Status.State == "reconnecting", "PUT starts without an observation");
        var positives = f.Positives;
        f.Handler.Status = 1;
        f.Handler.BeforeReceipt = () => {
            if (transientInvisible) SetM04gObservation(f.Host, 3);
            SetM04gObservation(f.Host, null);
        };
        await f.Set("online");
        var snapshot = f.Bridge.ReadPublicationSnapshot(wakePublication: false);
        Check(snapshot.Observation is null, "online receipt cannot replace a newer null observation");
        Check(f.Publication.Status.State == "reconnecting" &&
            snapshot.SuspensionError == "privacy_publication.network_unavailable",
            "newer null must retain the existing reconnecting suspension");
        Check(f.Positives == positives, "null during PUT must block positive sends even when PUT starts null");
        await f.Publication.TickAsync();
        Check(f.Bridge.ReadPublicationSnapshot(wakePublication: false).Observation is null &&
            f.Publication.Status.State == "reconnecting" && f.Positives == positives,
            "next tick must remain suspended after a receipt loses to newer null");
    }

    private static Task IdentityPendingJournal()
    {
        using var f = new VisibilityResumeFixture();
        new PrivacyPublicationJournal(f.Root).Record("identityRequired", "privacy_publication.identity_pending");
        var lines = File.ReadAllLines(Path.Combine(f.Root, "realtime-sharing-diagnostics.log"));
        Check(lines.Length == 1 && lines[0].EndsWith("state=identityRequired reason=identity", StringComparison.Ordinal),
            "identity_pending must use reason=identity");
        return Task.CompletedTask;
    }

    private static async Task ChangedReceiptScope(bool changeAccount)
    {
        using var f = new VisibilityResumeFixture();
        await f.Start();
        var positives = f.Positives;
        SetM04gObservation(f.Host, 3);
        f.Handler.BeforeReceipt = () => {
            if (changeAccount)
                typeof(ScmAccountBridgeHost).GetField("_session", PrivateInstance)!.SetValue(f.Host,
                    f.Session with { Subject = "different-fixture" });
            else
                typeof(ScmAccountBridgeHost).GetField("_generation", PrivateInstance)!.SetValue(f.Host, f.Host.Generation + 1);
        };
        try
        {
            await f.Host.SetPresenceVisibilityAuthorityAsync(f.Owner, f.Generation, PlayerPresenceVisibilityMode.Online, default);
            throw new Exception("changed owner/session accepted successful receipt");
        }
        catch (AccountBridgeHostException error)
        {
            Check(error.Code == "presence.account_changed", "changed owner/session rejects receipt at the authority fence");
        }
        await f.Publication.TickAsync();
        Check(f.Positives == positives && f.Publication.Status.State != "applied", "changed scope stays fail-closed");
    }

    private sealed class VisibilityResumeFixture : IDisposable
    {
        internal readonly string Root = Directory.CreateTempSubdirectory("cx-l11-").FullName;
        internal readonly ScmOAuthSession Session = new("fixture-scm", "fixture-subject", "Fixture", "synthetic-only",
            DateTimeOffset.UtcNow.AddMinutes(5), [], GameIdentityHandle: "Fixture");
        internal readonly VisibilityReceiptHandler Handler = new();
        internal readonly ScmAccountBridgeHost Host;
        internal readonly BridgeAccountContext Owner;
        internal readonly long Generation;
        internal readonly PrivacyPublication Publication;
        internal readonly PresenceVisibilityBridge Bridge;
        private readonly LocalPrivacyStore _store;
        private readonly PresenceVisibilityStore _visibility;
        internal int Positives;
        internal int Clears;

        internal VisibilityResumeFixture()
        {
            var endpoint = new Uri("https://presence.invalid/");
            var options = new ScmOAuthOptions("fixture-scm", endpoint, endpoint, endpoint,
                "fixture", "fixture", "fixture", "/fixture-callback");
            Host = new(new OAuthPkceClient(new ScmHttpClient(Handler), new NoM04gVault(), options),
                new ScmProfileCacheStore(), "fixture", () => null, initialSession: Session);
            Owner = Host.GameplayTimeContext!;
            Generation = Host.Generation;
            _store = new(Root);
            _visibility = new(Root);
            _store.Save(Owner, 0, Guid.NewGuid().ToString("N"), new(true,
                new(PlayerSharedStateFields.Presence, false, true, []), new(PlayerSharedStateFields.None, false)), () => true);
            PrivacyPublicationInput? Input() => Host.GameplayTimeContext == Owner && Host.Generation == Generation
                ? new(Owner, Generation, "Fixture", true, null, GameLogSessionSnapshot.Empty) : null;
            PresenceVisibilityBridge? bridge = null;
            Publication = new(_store, Input, (_, body, _) => {
                if (body.GetProperty("online").GetBoolean()) Positives++; else Clears++;
                return Task.CompletedTask;
            }, startTimer: false,
                visibilitySnapshot: () => bridge!.ReadPublicationSnapshot(wakePublication: false),
                confirmExplicitSharing: (o, g) => bridge!.ConfirmObservedModeForExplicitSharing(o, g),
                consumeExplicitOnlineResume: (o, g) => bridge!.ConsumeExplicitOnlineResume(o, g));
            Bridge = Host.ConfigurePublicationVisibility(read => new(_visibility,
                () => (Host.GameplayTimeContext, Host.Generation), Publication.ChangeVisibilityAsync,
                Host.SetPresenceVisibilityAuthorityAsync, () => Host.PresenceRequiresSessionConfirmation, read,
                Publication.ObserveVisibility));
            bridge = Bridge;
            SetM04gObservation(Host, 1);
        }

        internal async Task Start()
        {
            await Publication.ApplyAsync(Owner, Generation, 1, default);
            Check(Publication.Status.State == "applied" && Positives == 1, "initial sharing is active");
        }
        internal bool PausedOnDisk() => new LocalPrivacyStore(Root).IsPublicationPaused(Owner);
        internal async Task<BridgeEnvelope> SetResponse(string mode) => (await Bridge.DispatchAsync(
            BridgeEnvelope.Request("presence.set", Guid.NewGuid().ToString("N"), Generation,
                new { schemaVersion = 1, expectedRevision = _visibility.Read().Revision, mode }, Owner))).Response;
        internal async Task Set(string mode)
        {
            var response = await SetResponse(mode);
            Check(response.Error is null && response.Payload.GetProperty("state").GetString() == "ready",
                "presence write must be acknowledged");
        }
        public void Dispose()
        {
            Bridge.Dispose(); Publication.Dispose(); Host.Dispose(); Handler.Dispose();
            Directory.Delete(Root, true);
        }
    }

    private sealed class VisibilityReceiptHandler : HttpMessageHandler
    {
        internal int Status = 1;
        internal Action? BeforeReceipt;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri?.Host == "presence.invalid" && request.Method == HttpMethod.Put &&
                request.RequestUri.AbsolutePath.EndsWith("/presence/status", StringComparison.Ordinal), "unexpected fixture request");
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            Check(body.RootElement.GetProperty("status").GetInt32() == Status, "requested status matches receipt");
            BeforeReceipt?.Invoke();
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                signInStatus = Status, timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(), anonymous = false
            }) };
        }
    }
}
