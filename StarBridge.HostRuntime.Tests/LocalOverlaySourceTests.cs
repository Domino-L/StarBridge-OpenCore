using System.IO;
using System.Security.Cryptography;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;

internal static class LocalOverlaySourceTests
{
    internal static readonly DateTimeOffset Start = new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);
    internal static async Task Run()
    {
        foreach (var test in new (string Name, Action Test)[] {
            ("known inactive mode is distinct from failed or unknown mode", Modes),
            ("actual log evidence supplies only local display facts", ActualFacts),
            ("listening, uncertainty, expiry and mode generations revoke frames", Revocation),
            ("changing Handle revokes old frames without account promotion", Profiles),
            ("module choices retain missing and hidden sources without remote grants", Modules),
            ("corrupt identity metadata remains unavailable without replacement", Corruption),
            ("stable selection revokes old observations and module frames on replacement", Replacement),
            ("replacement during capture and failed selection suppress account fallback", ReplacementDuringCapture)
        }) { test.Test(); Console.WriteLine("PASS local overlay source: " + test.Name); }
        await Retirement();
        Console.WriteLine("PASS local overlay source: retirement drains actual capture and retained-frame reads");
    }
    private static void Modes()
    {
        using var f = new Fixture(); f.Mode = (false, 2);
        Check(f.Source.Capture() is null, "Only a stable known inactive mode selects the existing account path.");
        f.Mode = (false, -1); Check(f.Source.Capture()?.Read().State == "unavailable", "An unknown mode cannot choose account fallback.");
        f.SourceModeHook = () => throw new InvalidOperationException("synthetic mode error");
        Check(f.Source.Capture()?.Read().State == "unavailable", "A failed mode read suppresses account sources.");
        f.SourceModeHook = () => f.Mode = (true, 3); f.Mode = (false, 2);
        Check(f.Source.Capture() is not null, "A switch during the inactive read cannot acknowledge account selection.");
    }
    private static void Replacement()
    {
        using var first = new Fixture(); using var second = new Fixture();
        first.Enable(); second.Enable();
        LocalOverlaySourceRuntime? selected = first.Source;
        var binding = new LocalOverlaySourceBinding(() => selected);
        var firstFrame = binding.Capture()!;
        var modules = firstFrame.ReadModules(Workspace()).Frame!;
        Check(firstFrame.Read().State == "ready", "Binding retains actual local parser facts.");
        selected = null;
        Check(binding.Capture()?.Read().State == "unavailable" && firstFrame.Read().State == "unavailable" &&
            modules.ReadModules(Start).Values.All(c => !c.Source.Available),
            "Recovery gap invalidates both retained frames, without selecting account sources.");
        selected = second.Source;
        var secondFrame = binding.Capture()!;
        Check(secondFrame.Read().State == "ready" && firstFrame.Read().State == "unavailable" &&
            secondFrame.ReadModules(Workspace()).Frame!.OwnerKey != modules.OwnerKey,
            "Same Native binding selects replacement without reusing native continuity or old observations.");
        // Changing only the selected owner does not stop it or grant a local mode.
        second.Mode = (false, 2);
        Check(binding.Capture() is null && secondFrame.Read().State == "unavailable",
            "Only the actual current owner's confirmed non-local mode permits account selection.");
    }
    private static void ReplacementDuringCapture()
    {
        using var first = new Fixture(); using var second = new Fixture();
        LocalOverlaySourceRuntime? selected = first.Source;
        var fail = false;
        var binding = new LocalOverlaySourceBinding(() => fail ? throw new InvalidOperationException("synthetic") : selected);
        first.Mode = (false, 2);
        first.SourceModeHook = () => selected = second.Source;
        Check(binding.Capture()?.Read().State == "unavailable", "Old owner's null cannot authorize account fallback after replacement.");
        second.Enable(); var frame = binding.Capture()!;
        Check(frame.Read().State == "ready", "Replacement obtains fresh facts.");
        fail = true;
        Check(binding.Capture()?.Read().State == "unavailable" && frame.Read().State == "unavailable" &&
            frame.ReadModules(Workspace()).FailureCode == "overlay.identity_unavailable",
            "Failed owner lookup suppresses new and retained facts, without throwing into Native.");
    }
    private static void ActualFacts()
    {
        using var f = new Fixture();
        Check(f.Source.Capture()?.Read() is { State: "waiting", Handle: null }, "A confirmed profile does not enable listening.");
        f.Enable(); var frame = f.Source.Capture()!; var value = frame.Read();
        Check(value is { State: "ready", Handle: "Pilot-Example" } && value.Session.Server.State == "connected" &&
            value.Session.Ship.Key == "ANVL_Arrow", "The actual local parser provides server and ship facts without SCM.");
        var hash = f.Hash(); frame.Read(); frame.ReadModules(Workspace());
        Check(hash.SequenceEqual(f.Hash()) && !Directory.Exists(Path.Combine(f.Root, "account")) &&
            !Directory.Exists(Path.Combine(f.Root, "local-gameplay-time-v1")), "Display capture has no account, statistics or setting-write side effects.");
        f.Process = new("notRunning"); f.Game.Sample();
        Check(frame.Read().State == "unavailable" && f.Source.Capture()?.Read() is { State: "notRunning", Handle: "Pilot-Example" } after &&
            after.Session == GameLogSessionSnapshot.Empty, "Game exit clears live facts but retains explicit local identity.");
    }
    private static void Revocation()
    {
        using var f = new Fixture(); f.Enable(); var frame = f.Source.Capture()!;
        File.AppendAllText(f.Log, "unfinished nickname="); f.Game.Sample();
        Check(frame.Read().State == "unavailable" && f.Source.Capture()?.Read().State == "waiting", "Partial evidence revokes the ready frame.");
        f.Write(); f.Game.Sample(); frame = f.Source.Capture()!;
        f.Clock.Now = Start.AddSeconds(11);
        Check(frame.Read().State == "unavailable" && f.Source.Capture()?.Read().State == "waiting", "Expired facts are not retained as current.");
        f.Clock.Now = Start; f.Game.Sample(); frame = f.Source.Capture()!;
        f.Mode = (true, 2); Check(frame.Read().State == "unavailable", "Mode generations cannot borrow a retained frame.");
        f.Game.Sample(); Check(f.Source.Capture()?.Read().State == "ready", "The new generation obtains its own actual observation.");
        f.Game.ApplyListening(f.Key, false);
        Check(f.Source.Capture()?.Read() is { State: "waiting", Handle: null } stopped && stopped.Session == GameLogSessionSnapshot.Empty,
            "Stopping listening exposes no old game fields.");
    }
    private static void Profiles()
    {
        using var f = new Fixture(); f.Enable(); var frame = f.Source.Capture()!;
        var key = frame.ReadModules(Workspace()).Frame!.OwnerKey;
        f.Write("Other-Pilot", "200"); f.Game.Sample();
        Check(frame.Read().State == "unavailable" && f.Source.Capture()?.Read().State == "unavailable", "A new Handle is not auto-activated.");
        f.Confirm(); f.Game.Sample(); var second = f.Source.Capture()!;
        Check(second.Read().Handle == "Other-Pilot" && second.ReadModules(Workspace()).Frame!.OwnerKey != key,
            "Independent local identities have distinct process-local native continuity, not account IDs.");
        f.Write(); f.Game.Sample(); f.Confirm(); f.Game.Sample();
        Check(f.Source.Capture()?.Read().Handle == "Pilot-Example" && frame.Read().State == "unavailable" &&
            f.Identities.Read().Profiles.Count == 2, "Returning explicitly does not resurrect a retained old frame or merge profiles.");
    }
    private static void Modules()
    {
        using var f = new Fixture(); f.Enable(); var frame = f.Source.Capture()!;
        var preset = new OverlayPresetSources(OverlaySourceBinding.Automatic,
            modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding> {
                [OverlaySourceModule.Members] = new(OverlaySourceMode.Community, "not-this-local-owner", "synthetic-org"),
                [OverlaySourceModule.Chat] = new(OverlaySourceMode.Room)
            });
        var workspace = Workspace(preset); var read = frame.ReadModules(workspace);
        Check(read.FailureCode is null && read.Frame is not null, "Local module resolution reuses the actual existing resolver.");
        var content = read.Frame!.ReadModules(Start);
        Check(content[OverlaySourceModule.Overview].Source is { Mode: OverlaySourceMode.Local, Available: true } &&
            !content[OverlaySourceModule.Members].Source.Available && !content[OverlaySourceModule.Chat].Source.Available &&
            content.Values.All(c => c.Snapshot is null), "Missing explicit social sources stay empty, with no remote lease or fallback roster.");
        var hidden = frame.ReadModules(workspace with { Settings = workspace.Settings with { ShowMembers = false } }).Frame!.ReadModules(Start);
        Check(hidden[OverlaySourceModule.Members].Source.UnavailableReason == "module_hidden", "Hidden module choices remain hidden.");
        Check(frame.ReadModules(workspace with { IsPresetCorrupt = true }).FailureCode == "overlay.workspace_invalid_preset",
            "Corrupt presets cannot become usable local defaults.");
        var stale = read.Frame; f.Mode = (false, 2);
        Check(stale.ReadModules(Start).Values.All(c => !c.Source.Available), "A retained local module frame cannot authorize display after mode switch.");
    }
    private static void Corruption()
    {
        using var f = new Fixture(); f.Enable(); var frame = f.Source.Capture()!;
        var path = Path.Combine(f.Root, "device", "local-first-use-v1", "state.bin"); File.WriteAllBytes(path, [1, 3, 5]);
        Check(frame.Read().State == "unavailable" && f.Source.Capture()?.Read().State == "unavailable" &&
            File.ReadAllBytes(path).SequenceEqual(new byte[] { 1, 3, 5 }), "Unreadable identity state is not replaced, zeroed or promoted to an anonymous account.");
    }
    private static async Task Retirement()
    {
        foreach (var retained in new[] { false, true })
        {
            using var f = new Fixture(); f.Enable(); var frame = f.Source.Capture()!; var hash = f.Hash();
            var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            f.SourceModeHook = () => { started.TrySetResult(); Check(release.Task.Wait(TimeSpan.FromSeconds(5)), "Bounded fixture wait expired."); };
            var reading = Task.Run(() => { if (retained) frame.Read(); else f.Source.Capture(); });
            try
            {
                await started.Task.WaitAsync(TimeSpan.FromSeconds(5)); var stop = f.Source.RetireAsync();
                Check(!stop.IsCompleted && f.Source.Capture()?.Read().State == "unavailable", "Close rejects new display capture but waits for the actual admitted read.");
                release.TrySetResult(); await reading.WaitAsync(TimeSpan.FromSeconds(5)); await stop.WaitAsync(TimeSpan.FromSeconds(5));
                f.SourceModeHook = null;
                Check(frame.Read().State == "unavailable" && f.Source.Capture()?.Read().State == "unavailable" && hash.SequenceEqual(f.Hash()),
                    "Retired sources cannot render retained game fields or select account fallback.");
            }
            finally { release.TrySetResult(); await reading.WaitAsync(TimeSpan.FromSeconds(5)); f.SourceModeHook = null; }
        }
    }
    internal static InformationOverlayRuntimeWorkspace Workspace(OverlayPresetSources? sources = null) =>
        new(1, OverlayDisplaySettings.Default with { ShowSquads = true, ShowMembers = true, ShowChat = true }, [], "Alt+O", false,
            GameLogSessionSnapshot.Empty, "en", sources ?? new(OverlaySourceBinding.Automatic), SourcePresetsEnabled: true);
    internal sealed class Clock : TimeProvider
    { internal DateTimeOffset Now = Start; public override DateTimeOffset GetUtcNow() => Now; }
    internal sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-first-use-local-overlay", Guid.NewGuid().ToString("N"));
        internal string Log { get; }
        internal Clock Clock { get; } = new();
        internal (bool Active, long Generation) Mode = (true, 1);
        internal GameProcessSession Process = new("notRunning");
        internal Action? SourceModeHook;
        internal LocalFirstUseStore Identities { get; }
        internal LocalLogEvidenceOwner Evidence { get; }
        internal LocalGameLogRuntime Game { get; }
        internal LocalOverlaySourceRuntime Source { get; }
        internal string Key => Identities.Read().SelectedSourceKey!;
        internal Fixture()
        {
            Log = Path.Combine(Root, "install", "LIVE", "Game.log"); Directory.CreateDirectory(Path.GetDirectoryName(Log)!);
            Identities = new(Path.Combine(Root, "device"), Clock); Evidence = new(Identities, () => Process, Clock);
            Game = new(Identities, () => Mode, () => Process, Clock);
            Source = new(Identities, Game, () => { var mode = Mode; SourceModeHook?.Invoke(); return mode; }, Clock);
            Write(at: Start.AddMinutes(-1)); var candidate = Evidence.Select(Identities.Read().Revision, Log, "LIVE");
            Evidence.Confirm(candidate.SourceKey!, candidate.EvidenceKey!);
            Process = new("running", Log, Start, "synthetic-local-overlay-session"); Write();
        }
        internal void Write(string handle = "Pilot-Example", string id = "100", DateTimeOffset? at = null)
        {
            var stamp = $"<{at ?? Clock.Now:yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'}> ";
            File.WriteAllText(Log, stamp + $"nickname=\"{handle}\" playerGEID={id}\n" +
                stamp + "<Join PU> connected to shard[pub_sc_alpha_apse1_123]\n" +
                stamp + "<SHUDEvent_OnNotification> Added notification \"You joined channel 'Anvil Arrow : Pilot-Example'\"\n");
        }
        internal void Enable() => Game.ApplyListening(Key, true);
        internal void Confirm() { var candidate = Evidence.Refresh(Key); Evidence.Confirm(candidate.SourceKey!, candidate.EvidenceKey!); }
        internal byte[] Hash() => SHA256.HashData(File.ReadAllBytes(Path.Combine(Root, "device", "local-first-use-v1", "state.bin")));
        public void Dispose()
        {
            SourceModeHook = null; Game.Suspend(); Source.RetireAsync().GetAwaiter().GetResult();
            var full = Path.GetFullPath(Root); var parent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "starbridge-first-use-local-overlay"));
            if (Path.GetDirectoryName(full) != parent || !Guid.TryParseExact(Path.GetFileName(full), "N", out _) ||
                File.GetAttributes(full).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("Unsafe local overlay fixture cleanup.");
            Directory.Delete(full, recursive: true);
        }
    }
    internal static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
