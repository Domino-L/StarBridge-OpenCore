using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Settings;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Reminders;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class FirstUseRecoveryGuideTests
{
    internal static async Task Run()
    {
        await ProvenExit();
        using (var missing = new LocalAccountStopTests.Fixture())
        {
            new FirstUseModeStore(missing.Root).Save(0, Op(), "localPending", () => true);
            await Blocked(missing, "recoveryRequired");
        }
        using (var running = new LocalAccountStopTests.Fixture())
        {
            await AccountBridgeRuntime.CreateWithFirstUseModeAsync(running.Root, _ => Task.FromResult(running.Runtime));
            FileStream? writer = null;
            running.Transport.RevokeReply = () => writer = new FileStream(Path.Combine(running.Root,
                "first-use-mode-v1", "state.bin.lock"), FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            try
            {
                try { await running.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), running.Host.Generation); }
                catch (LocalFirstUseException error) when (error.Code == "firstUse.mode_write_failed") { }
            }
            finally { writer?.Dispose(); running.Transport.RevokeReply = null; }
            if (new FirstUseModeStore(running.Root).ReadRetirement()?.Owner.ReadExit() != "running")
                throw new InvalidOperationException("The running-owner fixture requires an actual running PID.");
            await Blocked(running, "recoveryRequired");
        }
        using (var corrupt = new LocalAccountStopTests.Fixture())
        {
            var directory = Path.Combine(corrupt.Root, "first-use-mode-v1"); Directory.CreateDirectory(directory);
            File.WriteAllBytes(Path.Combine(directory, "state.bin"), [42, 43, 44]);
            await Blocked(corrupt, "unavailable");
        }
    }

    private static async Task ProvenExit()
    {
        using var original = new LocalAccountStopTests.Fixture();
        await FirstUseModeRecoveryTests.ChildStop(original);
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(original.Root,
            _ => throw new InvalidOperationException("Recovery constructed online owners."), localGameProbe: () => new("notRunning"));
        var mode = cold.FirstUseMode!;
        using var application = new ApplicationPreferencesBridgeDispatcher(new ApplicationPreferencesStore(original.Root),
            new LocalDeviceSetupReaderTests.Startup(), () => mode.ControlGeneration);
        using var overlay = new OverlayBridgeDispatcher(new OverlaySettingsStore(original.Root), new OverlayWorkspaceStore(original.Root),
            () => mode.ControlGeneration, () => throw new InvalidOperationException("Device recovery read an account."),
            new LocalDeviceSetupReaderTests.Native());
        using var notices = new NotificationSettingsBridgeDispatcher(original.Root, () => mode.ControlGeneration);
        using var reminder = new ContinuousPlayReminderRuntime(original.Root,
            () => throw new InvalidOperationException("Recovery sampled a game."), new LocalDeviceSetupReaderTests.ReminderSink());
        cold.ConfigureFirstUseDeviceSetup(application, overlay, notices, reminder);
        await using var native = new NativeAccountRuntimeBinding(cold);
        using var guide = new FirstUseBridgeDispatcher(original.Root, cold, native,
            new FirstUseStartupReader(original.Root, () => new("fresh", "0.7.2")), new NoPicker(),
            _ => throw new InvalidOperationException("Local recovery configured online business."), () => "en");
        var before = new LocalFirstUseStore(original.Root).Read();
        var read = await guide.DispatchAsync(BridgeEnvelope.Request("onboarding.read", Op(), mode.ControlGeneration, new { schemaVersion = 1 }));
        Check(read.Response.Status == "ok" && mode.Current.State == "recoveryRequired" && !mode.LocalMode().Active,
            "Reading cannot implicitly recover the original stopped owner.");
        var facts = read.Response.Payload.GetProperty("facts");
        var request = BridgeEnvelope.Request("onboarding.execute", Op(), mode.ControlGeneration, new {
            schemaVersion = 1, expectedStateKey = read.Response.Payload.GetProperty("stateKey").GetString(), action = "applyMode",
            checkpoint = new { step = "mode", mode = "local", sourceKey = facts.GetProperty("sourceKey").GetString(),
                evidenceKey = facts.GetProperty("evidenceKey").GetString() }
        });
        var applied = await guide.DispatchAsync(request);
        Check(applied.Response.Status == "ok" && applied.Response.AccountContext is null && applied.Events.Count == 0 &&
            mode.Current.State == "local" && mode.LocalMode().Active && mode.Current.PublicationSuspended,
            "The actual guide's explicit local choice must recover an exactly proven stopped owner.");
        var after = new LocalFirstUseStore(original.Root).Read();
        Check(after.Progress is { Step: "mode", Mode: "local" } && after.Profiles.SequenceEqual(before.Profiles) &&
            after.Sources.SequenceEqual(before.Sources) && after.ActiveProfileId == before.ActiveProfileId &&
            original.Vault.Loads == 0 && original.Vault.Deletions == 0 && original.Transport.AllRequests == 0,
            "Guide recovery changes only explicit mode/progress, not profiles, authorization or online business.");
        Check((await guide.DispatchAsync(request with { CorrelationId = Op() })).Response.Status != "ok",
            "The old setup observation cannot be replayed after explicit recovery.");
        Console.WriteLine("PASS original recovery guide: actual exited owner receipt, explicit applyMode, no auth startup and preserved profiles");
    }

    private static async Task Blocked(LocalAccountStopTests.Fixture original, string expectedState)
    {
        var path = Path.Combine(original.Root, "first-use-mode-v1", "state.bin");
        var bytes = File.ReadAllBytes(path);
        var traffic = original.Transport.AllRequests; var loads = original.Vault.Loads; var deletions = original.Vault.Deletions;
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(original.Root,
            _ => throw new InvalidOperationException("Failed recovery constructed an account."), localGameProbe: () => new("notRunning"));
        var mode = cold.FirstUseMode!;
        using var application = new ApplicationPreferencesBridgeDispatcher(new ApplicationPreferencesStore(original.Root),
            new LocalDeviceSetupReaderTests.Startup(), () => mode.ControlGeneration);
        using var overlay = new OverlayBridgeDispatcher(new OverlaySettingsStore(original.Root), new OverlayWorkspaceStore(original.Root),
            () => mode.ControlGeneration, () => throw new InvalidOperationException("Failed recovery read an account."),
            new LocalDeviceSetupReaderTests.Native());
        using var notices = new NotificationSettingsBridgeDispatcher(original.Root, () => mode.ControlGeneration);
        using var reminder = new ContinuousPlayReminderRuntime(original.Root,
            () => throw new InvalidOperationException("Failed recovery sampled a game."), new LocalDeviceSetupReaderTests.ReminderSink());
        cold.ConfigureFirstUseDeviceSetup(application, overlay, notices, reminder);
        await using var native = new NativeAccountRuntimeBinding(cold);
        using var guide = new FirstUseBridgeDispatcher(original.Root, cold, native,
            new FirstUseStartupReader(original.Root, () => new("fresh", "0.7.2")), new NoPicker(),
            _ => throw new InvalidOperationException("Failed recovery configured business."), () => "en");
        var read = await guide.DispatchAsync(BridgeEnvelope.Request("onboarding.read", Op(), mode.ControlGeneration, new { schemaVersion = 1 }));
        Check(read.Response.Status == "ok" && mode.Current.State == expectedState && !mode.LocalMode().Active,
            "A read must expose no new mode authority.");
        var facts = read.Response.Payload.GetProperty("facts");
        var reply = await guide.DispatchAsync(BridgeEnvelope.Request("onboarding.execute", Op(), mode.ControlGeneration, new {
            schemaVersion = 1, expectedStateKey = read.Response.Payload.GetProperty("stateKey").GetString(), action = "applyMode",
            checkpoint = new { step = "mode", mode = "local", sourceKey = facts.GetProperty("sourceKey").GetString(),
                evidenceKey = facts.GetProperty("evidenceKey").GetString() }
        }));
        Check(reply.Response.Status != "ok" && !mode.LocalMode().Active && mode.Current.State == expectedState &&
            bytes.SequenceEqual(File.ReadAllBytes(path)) && original.Transport.AllRequests == traffic &&
            original.Vault.Loads == loads && original.Vault.Deletions == deletions,
            "Missing proof, running owner or corrupt state must be retained, not reset into local readiness.");
        original.RequireLocalStateUnchanged();
        Console.WriteLine("PASS original recovery guide: blocked " + expectedState + ", original records and authorization unchanged");
    }
    private static string Op() => Guid.NewGuid().ToString("N");
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private sealed class NoPicker : IFirstUseLogPicker
    { public Task<string?> PickAsync(string locale, CancellationToken token) => throw new InvalidOperationException("Recovery opened a picker."); }
}
