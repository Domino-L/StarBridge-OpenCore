using StarBridge.HostRuntime.Updates;

internal static class InstalledUpdateTransactionTests
{
    internal static async Task Verify()
    {
        Require(!FlutterReleaseUpdateSource.InstallationEnabled(typeof(InstalledUpdateTransactionTests).Assembly), "Installation enabled without compiled opt-in.");
        Require(FlutterInstallerPublisherVerifier.ResourceVersion("0.7.0                                             ", false) == new Version(0, 7, 0, 0),
            "Space-padded Inno version resource was rejected.");
        Require(FlutterInstallerPublisherVerifier.InstalledBinaryVersion("0.7.0+" + new string('a', 40)) == new Version(0, 7, 0, 0),
            "Signed .NET source revision was confused with a release number.");
        foreach (var value in new[] { "0.7.0+", "0.7.0+main", "0.7.0++1", "0.7.0+1/path" }) {
            try { FlutterInstallerPublisherVerifier.InstalledBinaryVersion(value); throw new Exception("Invalid signed binary version accepted."); }
            catch (InvalidDataException) { }
        }
        foreach (var failure in new[] { "none", "install", "probe", "registration", "owners", "handoff" })
        {
            using var fixture = new Fixture();
            var operations = new Operations(fixture) { Failure = failure };
            var transaction = new InstalledUpdateTransaction(fixture.Installation, fixture.Root);
            string? result = null;
            try {
                result = await transaction.ApplyAsync("0.7.0.1", operations, _ => {
                    if (File.ReadAllText(fixture.Executable) != "old") throw new Exception("Changed application before exit receipt.");
                    if (failure == "handoff") throw new IOException("fixture rejected receipt");
                    return Task.CompletedTask;
                });
            } catch (IOException) when (failure is "registration" or "handoff") { }
            if (failure == "none") {
                Require(result == "committed" && File.ReadAllText(fixture.Executable) == "new" && operations.Restarts == 0,
                    "Successful installed update did not commit.");
                Require(File.ReadAllText(Path.Combine(fixture.Root, "previous", "unins000.dat")) == "old-registration", "Old uninstaller not retained.");
            } else if (failure is "owners" or "handoff") {
                Require(File.ReadAllText(fixture.Executable) == "old" && operations.Installs == 0 && operations.Restores == 0 && operations.Restarts == 0,
                    "Unconfirmed exit modified or restarted the original client.");
            } else {
                Require(File.ReadAllText(fixture.Executable) == "old", "Failed installed update lost the original.");
                Require(File.ReadAllText(Path.Combine(fixture.Root, "failed", "starbridge_flutter.exe")) == "new", "Failed candidate was deleted rather than retained.");
                if (failure == "registration") {
                    operations.Failure = "none";
                    Require(await transaction.RecoverAsync(operations) == "rolled-back", "Registry recovery was not resumable.");
                } else Require(result == "rolled-back", "Failed startup did not roll back.");
                Require(operations.Restarts == 1 && operations.Registry == "old", "File and registration restoration diverged.");
                Require(await transaction.RecoverAsync(operations) == "rolled-back" && operations.Restarts == 1, "Final recovery replayed startup.");
            }
            Require(File.ReadAllText(fixture.UserData) == "do-not-touch", "Update changed user data.");
        }
        foreach (var phase in new[] { "installing", "rolling-back", "restored" })
        {
            using var fixture = new Fixture();
            var operations = new Operations(fixture);
            operations.CaptureRegistration(Path.Combine(fixture.Root, "registration.json"));
            if (phase != "restored") {
                Directory.Move(fixture.Installation, Path.Combine(fixture.Root, "previous"));
                if (phase == "installing") { Directory.CreateDirectory(fixture.Installation); File.WriteAllText(fixture.Executable, "partial"); }
            }
            InstalledUpdateFiles.Write(Path.Combine(fixture.Root, "installed-state.json"),
                new InstalledUpdateTransaction.State(1, fixture.Installation, "0.7.0.1", new string('A', 64), phase));
            Require(await new InstalledUpdateTransaction(fixture.Installation, fixture.Root).RecoverAsync(operations) == "rolled-back" &&
                File.ReadAllText(fixture.Executable) == "old", "Interrupted install could not recover " + phase);
        }
        using (var fixture = new Fixture()) {
            var record = new InstalledUpdateRegistration(fixture.Installation, "0.7.0", "StarBridge.Flutter", "\"" + Path.Combine(fixture.Installation, "unins000.exe") + "\"");
            record.RequireShape();
            foreach (var invalid in new[] { record with { Product = "StarBridge.Wpf" }, record with { Version = "0.7.0+1" },
                record with { UninstallCommand = "cmd.exe /c unins000.exe" }, record with { Directory = Path.GetPathRoot(fixture.Root)! } }) {
                try { invalid.RequireShape(); throw new Exception("Invalid registered installation accepted."); }
                catch (InvalidDataException) { }
            }
            var start = InstalledUpdateWindowsOperations.CreateInstallerStart(Path.Combine(fixture.Root, "installer.exe"), fixture.Installation, fixture.Root);
            Require(!start.UseShellExecute && start.CreateNoWindow && start.ArgumentList.Contains("/NOCLOSEAPPLICATIONS") &&
                start.ArgumentList.Contains("/NORESTART") && start.ArgumentList.Contains("/NORESTARTAPPLICATIONS") &&
                start.ArgumentList.Contains("/DIR=" + fixture.Installation) && !start.ArgumentList.Contains("/FORCECLOSEAPPLICATIONS"),
                "Installer could close unrelated apps, reboot Windows or select another destination.");
            var plan = new InstalledUpdatePlan(1, fixture.Installation, "0.7.0", Path.GetDirectoryName(fixture.UserData)! + "-data", 1, 1, 2, 2,
                "installer-" + new string('a', 32) + ".exe");
            plan.Validate(fixture.Root);
            foreach (var invalid in new[] { plan with { DataRoot = fixture.Installation }, plan with { DataRoot = fixture.Root + "/../client" },
                plan with { InstallerName = "../other.exe" }, plan with { ClientPid = 2 }, plan with { CurrentVersion = "0.7.0+1" } }) {
                try { invalid.Validate(fixture.Root); throw new Exception("Unsafe installed plan accepted."); }
                catch (InvalidDataException) { }
            }
            var duplicate = Path.Combine(fixture.Root, "duplicate.json");
            File.WriteAllText(duplicate, "{\"schemaVersion\":1,\"schemaVersion\":2}");
            try { InstalledUpdateFiles.Read<InstalledUpdatePlan>(duplicate); throw new Exception("Duplicate plan fields accepted."); }
            catch (InvalidDataException) { }
        }
        foreach (var phase in new[] { "committed", "rolled-back", "prepared", "installing", "restored" })
        {
            using var fixture = new Fixture();
            var plan = new InstalledUpdatePlan(1, fixture.Installation, "0.7.0", Path.GetDirectoryName(fixture.UserData)! + "-data", 1, 1, 2, 2,
                "installer-" + new string('a', 32) + ".exe");
            InstalledUpdateFiles.Write(Path.Combine(fixture.Root, InstalledUpdatePlan.FileName), plan);
            InstalledUpdateFiles.Write(Path.Combine(fixture.Root, "installed-state.json"),
                new InstalledUpdateTransaction.State(1, fixture.Installation, "0.7.0.1", new string('A', 64), phase));
            if (phase == "committed") {
                Directory.CreateDirectory(Path.Combine(fixture.Root, "previous"));
                File.WriteAllText(Path.Combine(fixture.Root, "previous", "starbridge_flutter.exe"), "old-backup");
            }
            var current = new InstalledUpdateRegistration(fixture.Installation, phase == "committed" ? "0.7.0.1" : "0.7.0", "StarBridge.Flutter",
                "\"" + Path.Combine(fixture.Installation, "unins000.exe") + "\"");
            try {
                FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, () => current);
                Require(phase is "committed" or "rolled-back" or "prepared", "Unresolved recovery material was deleted.");
                Require(!Directory.Exists(fixture.Root), "Completed cache did not retire on the next update.");
            } catch (IOException) when (phase is "installing" or "restored") {
                Require(Directory.Exists(fixture.Root), "Pending recovery workspace disappeared.");
            }
            Require(File.ReadAllText(fixture.Executable) == "old" && File.ReadAllText(fixture.UserData) == "do-not-touch",
                "Cache pruning escaped the owned update workspace.");
            try { FlutterInstalledUpdateInstallation.DeleteOwnedWorkspace(fixture.Installation, Path.GetDirectoryName(fixture.Installation)!);
                throw new Exception("Broad parent cleanup accepted."); }
            catch (InvalidDataException) { }
        }
    }

    private static void Require(bool value, string error) { if (!value) throw new Exception(error); }
    private sealed class Fixture : IDisposable
    {
        private readonly string _parent = Path.Combine(Path.GetTempPath(), "starbridge-installed-transaction-test-" + Guid.NewGuid().ToString("N"));
        internal string Installation { get; }
        internal string Root { get; }
        internal string Executable => Path.Combine(Installation, "starbridge_flutter.exe");
        internal string UserData => Path.Combine(_parent, "user-data.txt");
        internal Fixture() {
            Installation = Path.Combine(_parent, "client"); Root = Path.Combine(_parent, InstalledUpdateFiles.Prefix + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Installation); Directory.CreateDirectory(Root);
            File.WriteAllText(Executable, "old"); File.WriteAllText(Path.Combine(Installation, "unins000.dat"), "old-registration");
            File.WriteAllText(UserData, "do-not-touch");
        }
        public void Dispose() => Directory.Delete(_parent, true); // Exact newly-created TEMP fixture only.
    }
    private sealed class Operations(Fixture fixture) : IInstalledUpdateOperations
    {
        internal string Failure = "none", Registry = "old";
        internal int Installs, Restores, Restarts;
        public void ValidateOriginal() => Require(File.ReadAllText(fixture.Executable) == "old", "Wrong original.");
        public void CaptureRegistration(string path) => File.WriteAllText(path, Registry);
        public void RestoreRegistration(string path) {
            Restores++; if (Failure == "registration") throw new IOException("fixture registry locked");
            Registry = File.ReadAllText(path);
        }
        public Task WaitForOwnersAsync(CancellationToken token) {
            if (Failure == "owners") throw new OperationCanceledException(); return Task.CompletedTask;
        }
        public Task InstallAsync(CancellationToken token) {
            Installs++; Directory.CreateDirectory(fixture.Installation); File.WriteAllText(fixture.Executable, "new"); Registry = "new";
            if (Failure == "install") throw new IOException("fixture installer failed"); return Task.CompletedTask;
        }
        public Task<bool> ProbeAsync(string version, string nonce, CancellationToken token) => Task.FromResult(Failure is not ("probe" or "registration"));
        public Task StopCandidateAsync(CancellationToken token) => Task.CompletedTask;
        public Task RestartRestoredAsync(CancellationToken token) { Restarts++; return Task.CompletedTask; }
    }
}
