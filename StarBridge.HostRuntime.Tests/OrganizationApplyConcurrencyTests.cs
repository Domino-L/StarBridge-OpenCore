using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class OrganizationApplyConcurrencyTests
{
    private static readonly BridgeAccountContext Owner = new("test", "https://privacy.invalid", "organization-apply-fixture");

    internal static Task ConcurrentPause() => ConcurrentChange(pause: true);
    internal static Task ConcurrentWithdrawal() => ConcurrentChange(pause: false);

    private static async Task ConcurrentChange(bool pause)
    {
        // Cover both existing consent and the unasked official-only behavior.
        foreach (var consented in new[] { false, true })
        {
            using var fixture = new Fixture(consented);
            using var admission = await fixture.Store.PositiveAdmission.EnterAsync(default);
            // ApplyAsync runs synchronously up to the occupied admission. A second
            // Store represents the other channel: same file lock, separate admission.
            var applying = fixture.Publisher.ApplyAsync(Owner, 1, fixture.Revision, default, preservePause: true, firstOfficialDefault: true);
            Check(!applying.IsCompleted, "Organization apply must be waiting at admission.");
            var other = new LocalPrivacyStore(fixture.Root);
            if (pause) await other.SetPublicationPausedAsync(Owner, fixture.Revision, true, () => true);
            else await other.SetPublicationConsentAsync(Owner, fixture.Revision, false, () => true);
            var concurrentBytes = File.ReadAllBytes(fixture.FilePath);
            Check(other.Read(Owner).Revision == fixture.Revision, "Concurrent metadata does not increment revision.");
            admission.Dispose();
            string? conflict = null;
            try { await applying.WaitAsync(TimeSpan.FromSeconds(5)); }
            catch (LocalPrivacyException error) { conflict = error.Code; }
            Check(concurrentBytes.SequenceEqual(File.ReadAllBytes(fixture.FilePath)),
                "Organization apply must leave the concurrent metadata file byte-for-byte unchanged.");
            var reopened = new LocalPrivacyStore(fixture.Root);
            Check(reopened.Read(Owner).Revision == fixture.Revision &&
                reopened.IsPublicationPaused(Owner) == pause &&
                reopened.HasPublicationConsent(Owner) == (pause && consented) &&
                reopened.IsPublicationRevoked(Owner) == !pause,
                "Concurrent consent/pause and settings revision must survive reopening.");
            Check(fixture.Sends == 0, "Abandoned organization apply must not publish.");
            Check(conflict == "privacy_local.conflict", "Changed metadata must return the existing conflict error.");
        }
    }

    internal static async Task NoConcurrentChange()
    {
        foreach (var consented in new[] { false, true })
        {
            using var fixture = new Fixture(consented);
            using var admission = await fixture.Store.PositiveAdmission.EnterAsync(default);
            var applying = fixture.Publisher.ApplyAsync(Owner, 1, fixture.Revision, default, preservePause: true, firstOfficialDefault: true);
            Check(!applying.IsCompleted, "Control must also wait at admission.");
            admission.Dispose();
            await applying.WaitAsync(TimeSpan.FromSeconds(5));
            // Explicit automatic four-field defaults may grant unasked consent.
            // Concurrent metadata must still prevent that grant.
            Check(fixture.Store.HasPublicationConsent(Owner) && !fixture.Store.IsPublicationPaused(Owner) &&
                fixture.Store.Read(Owner).Revision == fixture.Revision && fixture.Sends == 1,
                "Without a concurrent change, organization apply retains its existing behavior.");
        }
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "organization-apply-" + Guid.NewGuid().ToString("N"));
        internal LocalPrivacyStore Store { get; }
        internal PrivacyPublication Publisher { get; }
        internal long Revision { get; }
        internal int Sends { get; private set; }
        internal string FilePath => Directory.GetFiles(Path.Combine(Root, "privacy-local-v1"), "*.json").Single();

        internal Fixture(bool consented)
        {
            Store = new(Root);
            var target = new OfficialFleetRealtimeTarget("synthetic", 7, "TEST", "scm-observed-membership-row-v1:1");
            var settings = new LocalPrivacySettings(true, new(PlayerSharedStateFields.None, false, false, []),
                new(PlayerSharedStateFields.None, false),
                OfficialFleet: new(target, CommunityRealtimeScope.SupportedFields, "initial", Guid.NewGuid().ToString("N")));
            Revision = Store.Save(Owner, 0, Guid.NewGuid().ToString("N"), settings, () => true).Revision;
            if (consented) Store.SetPublicationConsent(Owner, Revision, true, () => true);
            var input = new PrivacyPublicationInput(Owner, 1, "Synthetic", true, "LIVE",
                new(new("connected", "US", "synthetic"), new("confirmed", "Test"), new("confirmed", "Test", "Test")),
                AppPresenceConfirmed: true);
            Publisher = new(Store, () => input, (_, _, _) => { Sends++; return Task.CompletedTask; }, startTimer: false);
        }

        public void Dispose() => Publisher.Dispose();
    }
}
