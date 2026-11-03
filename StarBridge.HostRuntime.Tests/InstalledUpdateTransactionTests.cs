using StarBridge.HostRuntime.Updates;

internal static class InstalledUpdateTransactionTests
{
    internal static async Task Verify()
    {
        VerifySupersededCompletedUpdate();
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

    internal static void VerifySupersededCompletedUpdate()
    {
        foreach (var phase in new[] { "committed", "installing", "restored", "rolled-back" }) {
            using var fixture = new Fixture();
            var plan = new InstalledUpdatePlan(1, fixture.Installation, "0.7.0.1", Path.GetDirectoryName(fixture.UserData)! + "-data",
                1, 1, 2, 2, "installer-" + new string('a', 32) + ".exe");
            InstalledUpdateFiles.Write(Path.Combine(fixture.Root, InstalledUpdatePlan.FileName), plan);
            InstalledUpdateFiles.Write(Path.Combine(fixture.Root, "installed-state.json"),
                new InstalledUpdateTransaction.State(1, fixture.Installation, "0.7.0.2", new string('A', 64), phase));
            var backup = Path.Combine(fixture.Root, "previous");
            Directory.CreateDirectory(backup);
            File.WriteAllText(Path.Combine(backup, "backup.txt"), "preserve-recovery");
            var current = new InstalledUpdateRegistration(fixture.Installation, "0.7.0.3", "StarBridge.Flutter",
                "\"" + Path.Combine(fixture.Installation, "unins000.exe") + "\"");
            if (phase == "committed") {
                FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, () => current);
                Require(!Directory.Exists(fixture.Root), "Superseded completed transaction still blocks updates.");
                var archives = Directory.GetDirectories(Path.GetDirectoryName(fixture.Root)!, ".starbridge-retired-update-*");
                Require(archives.Length == 1 && File.ReadAllText(Path.Combine(archives[0], "previous", "backup.txt")) == "preserve-recovery",
                    "Superseded recovery backup was not preserved.");
                FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, () => current);
            } else {
                try { FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, () => current); throw new Exception("Unresolved transaction bypassed."); }
                catch (IOException) { }
                Require(Directory.Exists(fixture.Root), "Unresolved recovery was moved.");
            }
            Require(File.ReadAllText(fixture.Executable) == "old" && File.ReadAllText(fixture.UserData) == "do-not-touch", "Archival changed installed or user data.");
        }
        VerifyAbandonedWorkspace();
    }

    // A real laptop stayed on "could not be prepared" for weeks over one of these.
    private static void VerifyAbandonedWorkspace()
    {
        static InstalledUpdateRegistration NotRead() => throw new Exception("A cache without a journal read the registration.");
        InstalledUpdatePlan Plan(string installation, string name) => new(1, installation, "0.7.1",
            Path.Combine(Path.GetDirectoryName(installation)!, "user-data"), 1, 1, 2, 2, name);
        var name = "installer-" + new string('a', 32) + ".exe";
        static void Age(string directory) => Directory.SetCreationTimeUtc(directory, DateTime.UtcNow.AddHours(-2));
        void Cases(string label, Action<Fixture> arrange, bool removed, Action<Fixture>? after = null, bool quietly = false)
        {
            using var fixture = new Fixture();
            File.WriteAllText(Path.Combine(fixture.Root, name), "cached");
            Age(fixture.Root);
            arrange(fixture);
            try {
                FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, NotRead);
                Require(removed || quietly, label + ": should have refused.");
            } catch (IOException) when (!removed && !quietly) { }
            after?.Invoke(fixture);
            Require(Directory.Exists(fixture.Root) != removed, label + ": wrong workspace outcome.");
            Require(File.ReadAllText(fixture.Executable) == "old" && File.ReadAllText(fixture.UserData) == "do-not-touch",
                label + ": cleanup escaped the workspace.");
        }
        Cases("installer only", _ => { }, true);
        // The real one: a laptop's interrupted download, one partial installer and nothing else,
        // with and without helper names to compare against.
        var interrupted = "installer-3baf47e4" + new string('0', 24) + ".exe";
        void Partial(Fixture fixture)
        {
            File.Delete(Path.Combine(fixture.Root, name));
            File.WriteAllBytes(Path.Combine(fixture.Root, interrupted), new byte[4096]);
        }
        Cases("interrupted download, old", Partial, true);
        Cases("interrupted download, old, with a helper set", fixture => {
            Partial(fixture);
            Directory.CreateDirectory(Path.Combine(fixture.Installation, "native_host", "maintenance"));
            File.WriteAllText(Path.Combine(fixture.Installation, "native_host", "maintenance", "StarBridge.UpdateHelper.exe"), "helper");
        }, true);
        Cases("interrupted download, recent", fixture => {
            Partial(fixture);
            Directory.SetCreationTimeUtc(fixture.Root, DateTime.UtcNow.AddMinutes(-29));
        }, false, fixture => Require(File.Exists(Path.Combine(fixture.Root, interrupted)), "A recent download was deleted."), quietly: true);
        Cases("interrupted download, just past the limit", fixture => {
            Partial(fixture);
            Directory.SetCreationTimeUtc(fixture.Root, DateTime.UtcNow.AddMinutes(-31));
        }, true);
        Cases("copied helper, no plan", fixture => {
            Directory.CreateDirectory(Path.Combine(fixture.Installation, "native_host", "maintenance"));
            File.WriteAllText(Path.Combine(fixture.Installation, "native_host", "maintenance", "StarBridge.UpdateHelper.exe"), "helper");
            Directory.CreateDirectory(Path.Combine(fixture.Root, "helper"));
            File.WriteAllText(Path.Combine(fixture.Root, "helper", "StarBridge.UpdateHelper.exe"), "copy");
            File.WriteAllText(Path.Combine(fixture.Root, "installer-manifest.json"), "{}");
        }, true);
        Cases("plan, helper never journaled", fixture =>
            InstalledUpdateFiles.Write(Path.Combine(fixture.Root, InstalledUpdatePlan.FileName), Plan(fixture.Installation, name)), true);
        Cases("journal without a plan", fixture => InstalledUpdateFiles.Write(Path.Combine(fixture.Root, "installed-state.json"),
            new InstalledUpdateTransaction.State(1, fixture.Installation, "0.7.2", new string('A', 64), "prepared")), false);
        foreach (var kept in new[] { "previous", "failed" })
            Cases(kept + " without a journal", fixture => {
                Directory.CreateDirectory(Path.Combine(fixture.Root, kept));
                File.WriteAllText(Path.Combine(fixture.Root, kept, "starbridge_flutter.exe"), "backup");
            }, false, fixture => Require(File.ReadAllText(Path.Combine(fixture.Root, kept, "starbridge_flutter.exe")) == "backup", "Backup was touched."));
        {
            using var fixture = new Fixture();
            var other = Path.Combine(Path.GetDirectoryName(fixture.Installation)!, "other-client");
            InstalledUpdateFiles.Write(Path.Combine(fixture.Root, InstalledUpdatePlan.FileName), Plan(other, name));
            File.WriteAllText(Path.Combine(fixture.Root, name), "cached");
            Age(fixture.Root);
            FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, NotRead);
            Require(File.Exists(Path.Combine(fixture.Root, InstalledUpdatePlan.FileName)) && File.Exists(Path.Combine(fixture.Root, name)),
                "Another installation's workspace was removed.");
        }
        // Whatever an update attempt does not create keeps the whole folder, and blocks nothing.
        foreach (var foreign in new[] { "holiday-photo.jpg", "installer-setup.exe", "installer-" + new string('a', 31) + ".exe", "installed-state.json.tmp", "notes.tmp" })
            Cases("foreign file " + foreign, fixture => File.WriteAllText(Path.Combine(fixture.Root, foreign), "mine"), false,
                fixture => Require(File.ReadAllText(Path.Combine(fixture.Root, foreign)) == "mine" && File.Exists(Path.Combine(fixture.Root, name)),
                    "A folder holding a foreign file lost content."), quietly: true);
        Cases("foreign file only, no installer", fixture => {
            File.Delete(Path.Combine(fixture.Root, name));
            File.WriteAllText(Path.Combine(fixture.Root, "document.txt"), "mine");
        }, false, fixture => Require(File.ReadAllText(Path.Combine(fixture.Root, "document.txt")) == "mine", "A foreign file was deleted."), quietly: true);
        Cases("foreign folder", fixture => {
            Directory.CreateDirectory(Path.Combine(fixture.Root, "photos"));
            File.WriteAllText(Path.Combine(fixture.Root, "photos", "a.jpg"), "mine");
        }, false, fixture => Require(File.Exists(Path.Combine(fixture.Root, "photos", "a.jpg")), "A foreign folder was deleted."), quietly: true);
        Cases("foreign file inside helper", fixture => {
            Directory.CreateDirectory(Path.Combine(fixture.Root, "helper"));
            File.WriteAllText(Path.Combine(fixture.Root, "helper", "a.jpg"), "mine");
        }, false, fixture => Require(File.Exists(Path.Combine(fixture.Root, "helper", "a.jpg")), "A foreign file in helper was deleted."), quietly: true);
        foreach (var mine in new[] { "personal.json", "my-tool.exe", "my-library.dll" })
            Cases("own file in helper " + mine, fixture => {
                Directory.CreateDirectory(Path.Combine(fixture.Installation, "native_host", "maintenance"));
                File.WriteAllText(Path.Combine(fixture.Installation, "native_host", "maintenance", "StarBridge.UpdateHelper.exe"), "helper");
                Directory.CreateDirectory(Path.Combine(fixture.Root, "helper"));
                File.WriteAllText(Path.Combine(fixture.Root, "helper", "StarBridge.UpdateHelper.exe"), "copy");
                File.WriteAllText(Path.Combine(fixture.Root, "helper", mine), "mine");
            }, false, fixture => Require(File.ReadAllText(Path.Combine(fixture.Root, "helper", mine)) == "mine", "A user file in helper was deleted."), quietly: true);
        Cases("folder inside helper", fixture => {
            Directory.CreateDirectory(Path.Combine(fixture.Root, "helper", "deep"));
            File.WriteAllText(Path.Combine(fixture.Root, "helper", "deep", "a.dll"), "mine");
        }, false, fixture => Require(File.Exists(Path.Combine(fixture.Root, "helper", "deep", "a.dll")), "A nested helper file was deleted."), quietly: true);
        Cases("every record an attempt can leave", fixture => {
            foreach (var record in new[] { "installer-manifest.json", "registration.json", "installed-transaction.lock",
                "installed-plan.json." + new string('b', 32) + ".tmp", "installed-state.json." + new string('c', 32) + ".tmp" })
                File.WriteAllText(Path.Combine(fixture.Root, record), "{}");
        }, true);
        FileStream? lease = null;
        Cases("installer leased by a live Host", fixture => lease = new FileStream(Path.Combine(fixture.Root, name), FileMode.Open, FileAccess.Read, FileShare.Read),
            false, fixture => { Require(File.Exists(Path.Combine(fixture.Root, name)), "Leased installer was deleted."); lease!.Dispose(); }, quietly: true);
        // Another Host may be mid-download with no installer yet: it stays and blocks nothing.
        Cases("recent, nothing written yet", fixture => {
            File.Delete(Path.Combine(fixture.Root, name));
            Directory.SetCreationTimeUtc(fixture.Root, DateTime.UtcNow);
        }, false, quietly: true);
        Semaphore? helper = null;
        Cases("live helper", fixture => {
            var id = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(fixture.Installation.ToUpperInvariant())));
            helper = new Semaphore(1, 1, "Local\\StarBridge.InstalledUpdate." + id);
            Require(helper.WaitOne(0), "Fixture gate was busy.");
        }, false, _ => { helper!.Release(); helper.Dispose(); });
        Cases("read-only file", fixture => {
            var file = Path.Combine(fixture.Root, "installer-manifest.json");
            File.WriteAllText(file, "{}");
            File.SetAttributes(file, FileAttributes.ReadOnly);
        }, false, fixture => {
            Require(File.Exists(Path.Combine(fixture.Root, name)), "A read-only workspace was partly deleted.");
            File.SetAttributes(Path.Combine(fixture.Root, "installer-manifest.json"), FileAttributes.Normal);
        }, quietly: true);
        // A file that appears after the check is not on the list: it stays, and so does its folder.
        {
            using var fixture = new Fixture();
            var listed = Path.Combine(fixture.Root, name);
            File.WriteAllText(listed, "cached");
            var late = Path.Combine(fixture.Root, "arrived-later.jpg");
            File.WriteAllText(late, "mine");
            FlutterInstalledUpdateInstallation.RetireListed(fixture.Root, [listed]);
            Require(!File.Exists(listed) && File.ReadAllText(late) == "mine", "Deletion went beyond the checked list.");
            File.Delete(late);
            FlutterInstalledUpdateInstallation.RetireListed(fixture.Root, []);
            Require(!Directory.Exists(fixture.Root), "An emptied workspace stayed.");
        }
        // A junction inside must refuse before anything goes, and its target must survive.
        {
            using var fixture = new Fixture();
            File.WriteAllText(Path.Combine(fixture.Root, name), "cached");
            var outside = Path.Combine(Path.GetDirectoryName(fixture.Installation)!, "outside");
            Directory.CreateDirectory(outside);
            File.WriteAllText(Path.Combine(outside, "kept.txt"), "kept");
            var link = Path.Combine(fixture.Root, "helper");
            Age(fixture.Root);
            using (var make = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("cmd.exe") {
                ArgumentList = { "/c", "mklink", "/J", link, outside }, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true })!) {
                make.WaitForExit();
                Require(make.ExitCode == 0, "Fixture junction was not created.");
            }
            try {
                try { FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, NotRead); throw new Exception("A junction inside was accepted."); }
                catch (IOException) { }
                Require(File.ReadAllText(Path.Combine(outside, "kept.txt")) == "kept" && File.Exists(Path.Combine(fixture.Root, name)),
                    "A refused workspace lost files.");
            } finally { Directory.Delete(link, false); } // Remove the link alone before the fixture's recursive delete.
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
