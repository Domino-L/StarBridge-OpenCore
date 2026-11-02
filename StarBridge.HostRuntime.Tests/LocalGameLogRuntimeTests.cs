using System.Text.Json;
using System.Diagnostics;
using System.Runtime.InteropServices;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class LocalGameLogRuntimeTests
{
    private static readonly DateTimeOffset Start = new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);
    private static string Op() => Guid.NewGuid().ToString("N");
    private static string Line(string body, DateTimeOffset? at = null) => $"<{at ?? Start:yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'}> {body}\n";
    private static string Identity(string handle = "Pilot-Example", string id = "100", DateTimeOffset? at = null) =>
        Line($"nickname=\"{handle}\" playerGEID={id}", at);
    internal static void Run()
    {
        var tests = new (string Name, Action Test)[] {
            ("explicit saved listening choice and no identity bypass", Choice),
            ("real local session, stop, reopen and no implicit collection", LocalSession),
            ("Handle changes pause the old profile without merging", IdentityChange),
            ("strict current records, incomplete lines and uncertainty", StrictEvidence),
            ("changed source links and resource bounds revoke readiness", SourceGuards),
            ("source, mode, process and clock generations revoke observations", Generations),
            ("one sampler selects local or account, never both", SamplingSlot),
            ("mode changes during account reads revoke late projections", AccountReadRace)
        };
        foreach (var test in tests) { test.Test(); Console.WriteLine("PASS first-use local game runtime: " + test.Name); }
    }

    private static void Choice()
    {
        using var f = new Fixture();
        var missing = f.Select();
        Expect("firstUse.evidence_required", () => f.Local.ApplyListening(missing.SourceKey!, true));
        Require(f.Store.Read().Sources.Single().ListeningEnabled is null && f.Store.Read().Profiles.Count == 0,
            "Enabling listening cannot create or confirm an identity.");
        Require(f.Local.ApplyListening(missing.SourceKey!, false) is { State: "stopped", ListeningEnabled: false } &&
            f.Store.Read().Sources.Single().NeedsFreshGameEvidence, "Explicit stopping is permitted without clearing the evidence gate.");
        f.Running(); File.WriteAllText(f.Log, Identity());
        var candidate = f.Evidence.Refresh(missing.SourceKey!); f.Evidence.Confirm(candidate.SourceKey!, candidate.EvidenceKey!);
        Require(f.Store.Read().Sources.Single().ListeningEnabled == false, "Identity confirmation does not enable listening.");
        using (var lease = new FileStream(f.Log, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            f.Local.Sample(); Require(f.Local.Current.State == "stopped", "A stopped reader does not open the log.");
        }
        Expect("firstUse.source_changed", () => f.Local.ApplyListening(Op(), true));
        Require(f.Local.ApplyListening(missing.SourceKey!, true).ListeningEnabled == true, "Only an explicit saved command enables it.");
        f.Mode = (false, 2);
        Expect("firstUse.context_changed", () => f.Local.ApplyListening(missing.SourceKey!, false));
        Require(f.Store.Read().Sources.Single().ListeningEnabled == true, "An inactive/stale mode cannot write preferences.");
    }

    private static void LocalSession()
    {
        using var f = new Fixture(); f.Confirm(); f.Running();
        File.WriteAllText(f.Log, SessionLines());
        Require(f.Local.Current.State == "choiceRequired", "A stored identity does not decide listening for the user.");
        f.Local.Sample(); Require(f.Local.Current.State == "choiceRequired", "An undecided reader has no implicit live state.");
        var key = f.Store.Read().SelectedSourceKey!;
        var ready = f.Local.ApplyListening(key, true);
        Require(ready is { State: "ready", Handle: "Pilot-Example", ListeningEnabled: true }, "No SCM login is required for real local recognition.");
        Require(ready.LocalSession.Server is { State: "connected", Region: "ASIA", Shard: "pub_sc_alpha_apse1_123" } &&
            ready.LocalSession.Ship is { State: "confirmed", Key: "ANVL_Arrow" }, "Existing server/ship rules provide actual current state.");
        Require(GameLogLocationCatalogTests.HasPack ? ready.LocalSession.Location.State == "confirmed" :
            ready.LocalSession.Location.State == "unknown", "Missing optional location data remains unknown, not invented.");
        Require(!Directory.Exists(Path.Combine(f.Root, "account")) &&
            Directory.EnumerateFiles(Path.Combine(f.Root, "device"), "*", SearchOption.AllDirectories).All(p =>
                Path.GetFileName(p) is "state.bin" or "state.bin.lock"),
            "Listening creates no account files, journal, statistics or history imports.");
        f.Process = new("notRunning"); f.Local.Sample();
        Require(f.Local.Current.State == "notRunning" && f.Local.Current.LocalSession == GameLogSessionSnapshot.Empty &&
            f.Store.Read().ActiveProfileId is not null, "Game exit clears only live fields, not the confirmed profile.");
        f.Reopen(); Require(f.Local.Current.ListeningEnabled == true, "The user's choice survives reopening.");
        f.Local.Sample(); Require(f.Local.Current.State == "notRunning", "Reopening never replays history as live game state.");
        var stopped = f.Local.ApplyListening(key, false);
        Require(stopped.State == "stopped" && stopped.LocalSession == GameLogSessionSnapshot.Empty, "Explicit stopping is immediate and saved.");
        f.Running(); f.Reopen(); f.Local.Sample();
        Require(f.Local.Current.State == "stopped", "A stopped choice is not automatically restarted.");
        Require(f.Local.ApplyListening(key, true).State == "ready", "The user can explicitly resume the saved source.");
    }

    private static string SessionLines() => Identity() +
        Line("<Join PU> connected to shard[pub_sc_alpha_apse1_123]") +
        Line("<RequestLocationInventory> Player[Pilot-Example] requested inventory for Location[Stanton1_Lorville]") +
        Line("<SHUDEvent_OnNotification> Added notification \"You joined channel 'Anvil Arrow : Pilot-Example'\"");

    private static void IdentityChange()
    {
        using var f = new Fixture(); f.Confirm(); f.Running(); File.WriteAllText(f.Log, SessionLines());
        var sourceKey = f.Store.Read().SelectedSourceKey!; f.Local.ApplyListening(sourceKey, true);
        var oldProfile = f.Store.Read().ActiveProfileId;
        File.AppendAllText(f.Log, Identity("Other-Pilot", "200")); f.Local.Sample();
        Require(f.Local.Current.State == "needsIdentity" && f.Local.Current.LocalSession == GameLogSessionSnapshot.Empty &&
            f.Store.Read().ActiveProfileId is null && f.Store.Read().Profiles.Count == 1,
            "Conflicting current identity suspends the old activation, preserving its independent profile.");
        File.WriteAllText(f.Log, Identity("Other-Pilot", "200"));
        var candidate = f.Evidence.Refresh(sourceKey); f.Evidence.Confirm(candidate.SourceKey!, candidate.EvidenceKey!);
        f.Local.Sample();
        Require(f.Local.Current is { State: "ready", Handle: "Other-Pilot" } && f.Store.Read().Profiles.Count == 2 &&
            f.Store.Read().ActiveProfileId != oldProfile, "Only explicit rechecking activates a separate profile; listening alone never merges data.");
    }

    private static void StrictEvidence()
    {
        foreach (var bad in new[] {
            Identity(id: "0"), Identity(id: "100 nickname=\"Other-Pilot\" playerGEID=200"),
            Identity(at: Start.AddSeconds(1)), "nickname=\"Pilot-Example\" playerGEID=100\n",
            Identity("Other-Pilot", "200"), Identity() + "unfinished identity nickname=",
            Identity() + Line("<SystemQuit> CSystem::Quit")
        })
        {
            using var f = new Fixture(); f.Confirm(); f.Running(); File.WriteAllText(f.Log, bad);
            f.Local.ApplyListening(f.Store.Read().SelectedSourceKey!, true);
            Require(f.Local.Current.State != "ready" && f.Local.Current.Handle is null &&
                f.Local.Current.LocalSession == GameLogSessionSnapshot.Empty,
                "Malformed/future/foreign/incomplete/quit evidence cannot expose current session fields.");
        }
        using var valid = new Fixture(); valid.Confirm(); valid.Running();
        File.WriteAllText(valid.Log, Identity(id: "000100") + Identity(id: "100") + Line("party nickname=\"Someone-Else\""));
        Require(valid.Local.ApplyListening(valid.Store.Read().SelectedSourceKey!, true).State == "ready",
            "Normalized numeric IDs remain one identity; unrelated nickname text cannot replace the local player.");
        File.AppendAllText(valid.Log, Identity().TrimEnd()); valid.Local.Sample();
        Require(valid.Local.Current.State == "reading" && valid.Local.Current.Handle is null, "Partial appends revoke the previous ready observation.");
        File.AppendAllText(valid.Log, "\n"); valid.Local.Sample(); Require(valid.Local.Current.State == "ready", "A completed consistent record restores readiness.");
        File.WriteAllBytes(valid.Log, [0xff, 0xfe, 0x0a]); valid.Local.Sample();
        Require(valid.Local.Current.State != "ready", "Strict UTF-8 damage does not fabricate a state.");
    }

    private static void Generations()
    {
        using var f = new Fixture(); f.Confirm(); f.Running(); File.WriteAllText(f.Log, SessionLines());
        f.Local.ApplyListening(f.Store.Read().SelectedSourceKey!, true);
        f.Clock.Now = Start.AddSeconds(11); Require(f.Local.Current.State == "waiting", "Published observations expire without sampling.");
        f.Clock.Now = Start.AddTicks(-1); Require(f.Local.Current.State == "waiting", "Clock rollback revokes a cached view.");
        f.Clock.Now = Start;
        f.Mode = (true, 2); Require(f.Local.Current.State == "waiting", "A new local mode generation cannot borrow old observations.");
        f.Local.Sample(); Require(f.Local.Current.State == "ready", "The new generation may obtain its own current evidence.");
        f.Mode = (false, 3); Require(f.Local.Current.State == "inactive", "Mode switch immediately hides local live observations.");
        f.Mode = (true, 4); f.ProbeHook = () => f.Mode = (false, 5); f.Local.Sample();
        Require(f.Local.Current.State == "inactive", "A mode switch during IO cannot publish a late view.");
        f.ProbeHook = null; f.Mode = (true, 6); f.Process = new("unknown"); f.Local.Sample();
        Require(f.Local.Current.State == "processUnknown", "Multiple/uncertain game processes remain uncertain.");
        f.Process = new("running", Path.Combine(f.Root, "install", "PTU", "Game.log"), Start, "ptu-session"); f.Local.Sample();
        Require(f.Local.Current.State == "otherSource", "Another version cannot borrow the selected source.");
        f.Running();
        var ptu = Path.Combine(f.Root, "install", "PTU", "Game.log"); Directory.CreateDirectory(Path.GetDirectoryName(ptu)!);
        File.WriteAllText(ptu, Identity("Other-Pilot", "200", Start.AddMinutes(-1)));
        f.Evidence.Select(f.Store.Read().Revision, ptu, "PTU");
        Require(f.Local.Current.State == "needsIdentity", "Changing source immediately invalidates the active local profile view.");
    }

    private static void SourceGuards()
    {
        using (var f = new Fixture())
        {
            f.Confirm(); f.Running(); File.WriteAllText(f.Log, SessionLines());
            var key = f.Store.Read().SelectedSourceKey!;
            Require(f.Local.ApplyListening(key, true).State == "ready", "Ordinary local source is readable.");
            var alias = Path.Combine(f.Root, "linked.log");
            Require(CreateHardLink(alias, f.Log, IntPtr.Zero), "The hard-link fixture must actually be created.");
            try
            {
                f.Local.Sample();
                Require(f.Local.Current.State == "unreadable" && f.Local.Current.Handle is null &&
                    f.Local.Current.LocalSession == GameLogSessionSnapshot.Empty,
                    "A link introduced after confirmation revokes the previous ready view.");
            }
            finally { File.Delete(alias); } // Owned fixture alias only; never delete its target.
            Require(File.ReadAllText(f.Log) == SessionLines(), "Rejected linked content is unchanged.");
            f.Local.Sample(); Require(f.Local.Current.State == "ready", "A safe source can obtain a fresh live view again.");
            using (var write = File.OpenWrite(f.Log)) write.SetLength(64L * 1024 * 1024 + 1);
            f.Local.Sample(); Require(f.Local.Current.State == "limit", "Large sources are bounded before any line reads.");
        }
        using (var f = new Fixture())
        {
            f.Confirm(); f.Running(); File.WriteAllText(f.Log, SessionLines());
            var key = f.Store.Read().SelectedSourceKey!;
            f.Local.ApplyListening(key, true);
            var version = Path.GetFullPath(Path.GetDirectoryName(f.Log)!);
            var moved = Path.GetFullPath(Path.Combine(f.Root, "install", "LIVE-fixture-target"));
            var install = Path.GetFullPath(Path.Combine(f.Root, "install"));
            Require(Path.GetDirectoryName(version) == install && Path.GetDirectoryName(moved) == install,
                "Directory moves must remain in this owned random fixture.");
            Directory.Move(version, moved);
            try
            {
                var start = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true,
                    RedirectStandardOutput = true, RedirectStandardError = true };
                foreach (var value in new[] { "-NoProfile", "-NonInteractive", "-Command",
                    "New-Item -ItemType Junction -Path '" + version.Replace("'", "''") + "' -Target '" +
                    moved.Replace("'", "''") + "' -ErrorAction Stop | Out-Null" }) start.ArgumentList.Add(value);
                using var process = Process.Start(start)!; process.WaitForExit();
                Require(process.ExitCode == 0, "The directory junction fixture must actually be created.");
                f.Local.Sample(); Require(f.Local.Current.State == "unreadable" && f.Local.Current.Handle is null,
                    "A substituted linked parent cannot retain confirmed local live evidence.");
                Require(File.ReadAllText(Path.Combine(moved, "Game.log")) == SessionLines(), "Rejected target is unchanged.");
            }
            finally
            {
                if (Directory.Exists(version) && File.GetAttributes(version).HasFlag(FileAttributes.ReparsePoint))
                    Directory.Delete(version); // Link only, not recursive.
                Directory.Move(moved, version);
            }
            f.Local.Sample(); Require(f.Local.Current.State == "ready", "Restored ordinary source is independently re-read.");
        }
    }

    private static void SamplingSlot()
    {
        using var f = new Fixture(); f.Confirm(); f.Running(); File.WriteAllText(f.Log, SessionLines());
        f.Local.ApplyListening(f.Store.Read().SelectedSourceKey!, true);
        var accountReads = 0;
        using var sampler = new GameLogRuntime(new GameLogSettingsStore(Path.Combine(f.Root, "account")),
            () => { accountReads++; return (null, 1); }, () => throw new InvalidOperationException("Unexpected account handle read"),
            () => throw new InvalidOperationException("Unexpected account process read"), f.Clock, startTimer: false);
        sampler.AttachLocalSlot(f.Local); sampler.Sample();
        Require(f.Local.Current.State == "ready" && accountReads == 0 && !Directory.Exists(Path.Combine(f.Root, "account")),
            "The existing sampler selects only the local reader, without an account lease or second timer.");
        Require(sampler.DetectedHandle is null && sampler.RecentDetectedHandle is null && sampler.ConfirmedVersion is null &&
            sampler.IdentityPolicyState == LocalIdentityCheckState.NotObserved && sampler.CurrentSession == GameLogSessionSnapshot.Empty &&
            sampler.CaptureFirstEntry() is null && sampler.SelectedPathForDiagnostics is null && accountReads == 0,
            "Local evidence never becomes account publication, qualification, diagnostics or achievement authority.");
        var request = BridgeEnvelope.Request("gameLog.read", Op(), 1, new { schemaVersion = 1 });
        Require(sampler.Dispatch(request).Response.Status == BridgeResponseStatuses.Error && accountReads == 0,
            "Account Bridge commands cannot start a second reader in local mode.");
        foreach (var active in new[] { false, true })
        {
            f.Mode = (active, -1); sampler.Sample();
            Require(f.Local.Current.State == "unavailable" && accountReads == 0 && sampler.DetectedHandle is null &&
                sampler.Dispatch(request).Response.Status == BridgeResponseStatuses.Error,
                "An invalid mode generation must not fall back to a retained account session.");
        }
        var failedMode = new LocalGameLogRuntime(f.Store, () => throw new InvalidOperationException("synthetic mode unavailable"));
        using var denied = new GameLogRuntime(new GameLogSettingsStore(Path.Combine(f.Root, "unavailable-account")),
            () => throw new InvalidOperationException("Account fallback on mode failure"), () => null, startTimer: false);
        denied.AttachLocalSlot(failedMode); denied.Sample();
        Require(failedMode.Current.State == "unavailable" && denied.CurrentSession == GameLogSessionSnapshot.Empty &&
            denied.Dispatch(request).Response.Status == BridgeResponseStatuses.Error &&
            !Directory.Exists(Path.Combine(f.Root, "unavailable-account")), "Mode read failure suppresses both IO and account commands.");
        f.Mode = (false, 2); sampler.Sample();
        Require(accountReads == 1 && f.Local.Current.State == "inactive", "Switching modes releases local sampling before returning to the existing account path.");
        ExpectOther<InvalidOperationException>(() => sampler.AttachLocalSlot(new(f.Store, () => f.Mode, () => f.Process, f.Clock)));
    }

    private static void AccountReadRace()
    {
        using var f = new Fixture(); f.Running(); f.Mode = (false, 1);
        File.WriteAllText(f.Log, SessionLines());
        var account = new BridgeAccountContext("test", "scm", "synthetic-mode-race");
        Action? onRead = null;
        using var sampler = new GameLogRuntime(new GameLogSettingsStore(Path.Combine(f.Root, "account")),
            () => { var action = onRead; onRead = null; action?.Invoke(); return (account, 1); },
            () => "Pilot-Example", () => f.Process, f.Clock, startTimer: false);
        sampler.AttachLocalSlot(f.Local);
        var select = BridgeEnvelope.Request("gameLog.select", Op(), 1, new { schemaVersion = 1, path = f.Log }, account);
        Require(sampler.Dispatch(select).Response.Status == BridgeResponseStatuses.Ok && sampler.DetectedHandle is not null,
            "The existing account path supplies real cached observations before a mode change.");
        var checks = new Func<bool>[] {
            () => sampler.DetectedHandle is null,
            () => sampler.RecentDetectedHandle is null,
            () => sampler.ConfirmedVersion is null,
            () => sampler.IdentityPolicyState == LocalIdentityCheckState.NotObserved,
            () => sampler.CurrentSession == GameLogSessionSnapshot.Empty,
            () => sampler.CaptureFirstEntry() is null,
            () => sampler.SelectedPathForDiagnostics is null
        };
        foreach (var check in checks)
        {
            f.Mode = (false, f.Mode.Generation + 1);
            onRead = () => f.Mode = (true, f.Mode.Generation + 1);
            Require(check() && f.Mode.Active && onRead is null,
                "A switch during the current-account check must revoke each late account projection.");
        }
    }

    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now { get; set; } = Start;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-first-use-local-game", Op());
        internal string Log { get; }
        internal Clock Clock { get; } = new();
        internal (bool Active, long Generation) Mode = (true, 1);
        internal GameProcessSession Process = new("notRunning");
        internal Action? ProbeHook;
        internal LocalFirstUseStore Store { get; private set; } = null!;
        internal LocalLogEvidenceOwner Evidence { get; private set; } = null!;
        internal LocalGameLogRuntime Local { get; private set; } = null!;
        internal Fixture()
        {
            Log = Path.Combine(Root, "install", "LIVE", "Game.log");
            Directory.CreateDirectory(Path.GetDirectoryName(Log)!); File.WriteAllText(Log, ""); Reopen();
        }
        private GameProcessSession Probe() { var old = Process; ProbeHook?.Invoke(); return old; }
        internal void Reopen()
        {
            Store = new(Path.Combine(Root, "device"), Clock);
            Evidence = new(Store, Probe, Clock);
            Local = new(Store, () => Mode, Probe, Clock);
        }
        internal LocalLogEvidenceObservation Select() => Evidence.Select(Store.Read().Revision, Log, "LIVE");
        internal void Confirm()
        {
            File.WriteAllText(Log, Identity(at: Start.AddMinutes(-1)));
            var candidate = Select(); Evidence.Confirm(candidate.SourceKey!, candidate.EvidenceKey!);
        }
        internal void Running() => Process = new("running", Log, Start, "fixture-game-session");
        public void Dispose()
        {
            Local.Suspend();
            var full = Path.GetFullPath(Root); var allowed = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "starbridge-first-use-local-game"));
            if (Path.GetDirectoryName(full) != allowed || !Guid.TryParseExact(Path.GetFileName(full), "N", out _) ||
                File.GetAttributes(full).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("Unsafe fixture cleanup target.");
            Directory.Delete(full, recursive: true);
        }
    }
    private static void Expect(string code, Action action)
    {
        try { action(); } catch (LocalFirstUseException error) when (error.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }
    private static void ExpectOther<T>(Action action) where T : Exception
    {
        try { action(); } catch (T) { return; }
        throw new InvalidOperationException("Expected " + typeof(T).Name);
    }
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    [DllImport("kernel32.dll", EntryPoint = "CreateHardLinkW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateHardLink(string file, string existing, IntPtr security);
}
