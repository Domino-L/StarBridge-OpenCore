using StarBridge.HostRuntime;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task OwnerGate073Admission()
    {
        using var f = new Fixture();
        var clock = new AdmissionOwnershipClock(); f.Original.DataOwnerTime = clock;
        await f.Start();
        var host = f.Original.Host!;
        host.EnableParticipantSynchronization(TimeSpan.FromMilliseconds(10));
        await host.GetCurrentAsync(default);
        Check(f.Coordinator.Reads == 0 && host.BusinessStartupDeferred,
            "Deferred candidate deliberately performs no automatic business ownership read.");
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        var stagedReads = f.Coordinator.Reads;
        Check(admission.TryActivate(), "Original business admission becomes live.");
        await CelebrationTestClock.Until(() => f.Coordinator.Reads > stagedReads);
        clock.Timestamp += TimeSpan.FromMinutes(4).Ticks;
        await CelebrationTestClock.Until(() => {
            try { host.ResolveLocalDataOwner(host.CurrentContext!); return true; }
            catch (StarBridge.HostRuntime.Privacy.LocalPrivacyOwnerUnavailableException) { return false; }
        });
        Check(host.ResolveLocalDataOwner(host.CurrentContext!) is not null,
            "Live business admission automatically starts ownership renewal after deferred startup.");
        await Finish(admission.RetireAsync());
    }
    internal static async Task OwnerGate073AdmissionOutage()
    {
        await OwnerGate073AdmissionInterruption(unknown: false);
        await OwnerGate073AdmissionInterruption(unknown: true);
    }

    private static async Task OwnerGate073AdmissionInterruption(bool unknown)
    {
        using var f = new Fixture();
        var clock = new AdmissionOwnershipClock(); f.Original.DataOwnerTime = clock;
        await f.Start();
        var host = f.Original.Host!;
        host.EnableParticipantSynchronization(TimeSpan.FromMilliseconds(10));
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        f.Coordinator.Fail = true; // Prevent an in-flight successful renewal from moving the baseline.
        Check(admission.TryActivate(), "Original business admission becomes live.");
        var outageReads = f.Coordinator.Reads;
        clock.Timestamp += TimeSpan.FromMinutes(4).Ticks;
        await CelebrationTestClock.Until(() => {
            if (f.Coordinator.Reads <= outageReads) return false;
            try { host.ResolveLocalDataOwner(host.CurrentContext!); return true; }
            catch (StarBridge.HostRuntime.Privacy.LocalPrivacyOwnerUnavailableException) { return false; }
        });
        Check(!host.BusinessStartupDeferred && admission.IsActive,
            "A transport outage within the thirty-minute owner lifetime keeps an already-live admission active.");
        var confirmed = f.Coordinator.Projection;
        if (unknown)
        {
            f.Coordinator.Projection = new("unavailable", "notEstablished", false, false, [], null);
            f.Coordinator.Fail = false;
        }
        else
        {
            // All subsequent attempts fail; no successful observation advances CheckedAt.
            for (var minute = 5; minute <= 31; minute++)
            {
                var previousReads = f.Coordinator.Reads;
                clock.Timestamp += TimeSpan.FromMinutes(1).Ticks;
                await CelebrationTestClock.Until(() => f.Coordinator.Reads > previousReads);
            }
            Check(!admission.IsActive && host.BusinessStartupDeferred,
                "Continuous network failure beyond thirty minutes must suspend admission and defer business startup.");
        }
        await CelebrationTestClock.Until(() => host.BusinessStartupDeferred);
        Check(!admission.IsActive, "An explicit unknown answer or expired failure lifetime pauses the same admission.");
        var reads = f.Coordinator.Reads;
        f.Coordinator.Projection = confirmed;
        f.Coordinator.Fail = false;
        await CelebrationTestClock.Until(() => f.Coordinator.Reads > reads && !host.BusinessStartupDeferred);
        Check(host.ResolveLocalDataOwner(host.CurrentContext!) is not null && admission.IsActive,
            "A temporary compatibility outage cannot strand an already-live business admission.");
        await Finish(admission.RetireAsync());
        Console.WriteLine("PASS OWNER-BINDING-073-R2 admission recovery: " + (unknown ? "explicit unknown" : "network lifetime"));
    }

}
