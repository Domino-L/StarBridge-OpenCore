using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using StarBridge.HostRuntime.Updates;

internal static partial class InstalledUpdateTransactionTests
{
    private static void VerifyStaleTransactions()
    {
        // Applying is also exercised under the helper's actual installing phase.
        foreach (var phase in new[] { "prepared", "applying", "installing", "committed", "rolled-back" })
        foreach (var manifest in new[] { 1, 2 })
        foreach (var version in new[] { "0.7.1", "0.7.3" }) {
            using var fixture = new Fixture();
            WriteStaleTransaction(fixture, phase, manifest);
            var current = Registration(fixture, version);
            var before = Snapshot(fixture.Root);
            FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, () => current);
            Require(!Directory.Exists(fixture.Root), $"{phase}/v{manifest}/{version}: old transaction still blocks preparation.");
            var archives = Directory.GetDirectories(Path.GetDirectoryName(fixture.Root)!, ".starbridge-retired-update-*");
            Require(archives.Length == 1 && before.SequenceEqual(Snapshot(archives[0])), "Retirement did not preserve the entire transaction.");
            // StageAsync calls this same prerequisite before creating a fresh workspace.
            // A second preparation must ignore the archive and keep its contents.
            FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, () => current);
            Require(before.SequenceEqual(Snapshot(archives[0])), "A later preparation changed the recovery archive.");
            RequireInstallationUnchanged(fixture);
        }
        foreach (var phase in new[] { "prepared", "applying", "installing", "committed", "rolled-back" })
        foreach (var version in new[] { "0.7.2", "0.7.2.1" }) {
            // A previous/failed tree makes prepared require recovery too. A committed
            // target and a rolled-back original are still ordinary completed cleanup.
            if (phase == "committed" && version == "0.7.2.1" || phase == "rolled-back" && version == "0.7.2") continue;
            using var fixture = new Fixture();
            WriteStaleTransaction(fixture, phase, 1);
            RefuseRetirement(fixture, Registration(fixture, version), "Previous update requires recovery.");
        }
        // Version spelling alone is not evidence of a different installation.
        using (var fixture = new Fixture()) {
            WriteStaleTransaction(fixture, "installing", 2);
            RefuseRetirement(fixture, Registration(fixture, "0.7.2.0"), "Previous update requires recovery.");
        }
        using (var fixture = new Fixture()) {
            WriteStaleTransaction(fixture, "applying", 2);
            var id = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(fixture.Installation.ToUpperInvariant())));
            using var gate = new Semaphore(1, 1, "Local\\StarBridge.InstalledUpdate." + id);
            Require(gate.WaitOne(0), "Fixture could not acquire the installation gate.");
            try { RefuseRetirement(fixture, Registration(fixture, "0.7.1"), "An installed update is already active."); }
            finally { gate.Release(); }
        }
        using (var fixture = new Fixture()) {
            WriteStaleTransaction(fixture, "prepared", 1);
            var reads = 0;
            var before = Snapshot(fixture.Root);
            try {
                FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation,
                    () => Registration(fixture, ++reads == 1 ? "0.7.1" : "0.7.2"));
                throw new Exception("Registration changed during retirement but was accepted.");
            } catch (IOException error) { Require(error.Message == "Installation registration changed.", "Wrong registration race rejection."); }
            Require(before.SequenceEqual(Snapshot(fixture.Root)), "Registration race moved recovery files.");
        }
        foreach (var directory in new[] { false, true }) {
            using var fixture = new Fixture();
            WriteStaleTransaction(fixture, "committed", 2);
            var id = Guid.NewGuid();
            var archive = Path.Combine(Path.GetDirectoryName(fixture.Root)!, ".starbridge-retired-update-" + id.ToString("N"));
            if (directory) { Directory.CreateDirectory(archive); File.WriteAllText(Path.Combine(archive, "kept.txt"), "occupied"); }
            else File.WriteAllText(archive, "occupied");
            var before = Snapshot(fixture.Root);
            try {
                FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, () => Registration(fixture, "0.7.1"), () => id);
                throw new Exception("Archive collision was accepted.");
            } catch (IOException error) { Require(error.Message == "Recovery archive already exists.", "Wrong collision rejection."); }
            Require(before.SequenceEqual(Snapshot(fixture.Root)) &&
                File.ReadAllText(directory ? Path.Combine(archive, "kept.txt") : archive) == "occupied",
                "Archive collision overwrote or moved files.");
            RequireInstallationUnchanged(fixture);
        }
        // Even malformed manifests do not participate in retirement.
        foreach (var manifest in new[] { 1, 2 }) {
            using var fixture = new Fixture();
            WriteStaleTransaction(fixture, "prepared", manifest);
            var manifestPath = Path.Combine(fixture.Root, "installer-manifest.json");
            File.WriteAllText(manifestPath, "not JSON: manifest contract must not matter");
            FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, () => Registration(fixture, "0.7.1"));
            Require(!Directory.Exists(fixture.Root), "Retirement tried to read a manifest.");
        }
        VerifyStaleLinks();
    }

    private static InstalledUpdateRegistration Registration(Fixture fixture, string version) =>
        new(fixture.Installation, version, "StarBridge.Flutter", "\"" + Path.Combine(fixture.Installation, "unins000.exe") + "\"");

    private static void WriteStaleTransaction(Fixture fixture, string phase, int manifest)
    {
        InstalledUpdateFiles.Write(Path.Combine(fixture.Root, InstalledUpdatePlan.FileName),
            new InstalledUpdatePlan(1, fixture.Installation, "0.7.2", Path.Combine(Path.GetDirectoryName(fixture.Root)!, "data"),
                1, 1, 2, 2, "installer-" + new string('a', 32) + ".exe"));
        InstalledUpdateFiles.Write(Path.Combine(fixture.Root, "installed-state.json"),
            new InstalledUpdateTransaction.State(1, fixture.Installation, "0.7.2.1", new string('A', 64), phase));
        // Representative v1/v2 records, deliberately without a trusted signature:
        // retirement cannot depend on either manifest contract or parse its contents.
        var manifestPath = Path.Combine(fixture.Root, "installer-manifest.json");
        if (manifest == 1)
            InstalledUpdateFiles.Write(manifestPath, new FlutterInstallerUpdateSource.Manifest("flutter", "windows-x64", "inno-setup",
                "0.7.2.1", "https://example.invalid/setup.exe", new string('a', 64), "v1 fixture", "fixture", "fixture"));
        else
            InstalledUpdateFiles.Write(manifestPath, new FlutterInstallerManifestV2("flutter", "windows-x64", "inno-setup",
                "0.7.2.1", [new("jp", "https://example.invalid/setup.exe")], 1, new string('a', 64), "v2 fixture", "fixture", "fixture"));
        foreach (var child in new[] { "previous", "failed", "helper" }) {
            Directory.CreateDirectory(Path.Combine(fixture.Root, child));
            File.WriteAllText(Path.Combine(fixture.Root, child, "kept.txt"), child + " recovery material");
        }
        File.WriteAllText(Path.Combine(fixture.Root, "registration.json"), "synthetic registration snapshot");
        File.WriteAllText(Path.Combine(fixture.Root, "installer-" + new string('a', 32) + ".exe"), "inert fixture");
    }

    private static string[] Snapshot(string root) => Directory.GetFiles(root, "*", SearchOption.AllDirectories)
        .Select(file => Path.GetRelativePath(root, file) + ":" + Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file))))
        .OrderBy(value => value, StringComparer.Ordinal).ToArray();

    private static void RefuseRetirement(Fixture fixture, InstalledUpdateRegistration current, string expected)
    {
        var before = Snapshot(fixture.Root);
        try {
            FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, () => current);
            throw new Exception("Recovery workspace was unexpectedly accepted.");
        } catch (IOException error) { Require(error.Message == expected, "Wrong retirement rejection: " + error.Message); }
        Require(before.SequenceEqual(Snapshot(fixture.Root)) &&
            Directory.GetDirectories(Path.GetDirectoryName(fixture.Root)!, ".starbridge-retired-update-*").Length == 0,
            "Refused transaction was moved or changed.");
        RequireInstallationUnchanged(fixture);
    }

    private static void RequireInstallationUnchanged(Fixture fixture) => Require(
        File.ReadAllText(fixture.Executable) == "old" && File.ReadAllText(fixture.UserData) == "do-not-touch",
        "Retirement changed the installation or personal data.");

    private static void VerifyStaleLinks()
    {
        foreach (var linkedRoot in new[] { false, true }) {
            using var fixture = new Fixture();
            WriteStaleTransaction(fixture, "applying", 2);
            var parent = Path.GetDirectoryName(fixture.Root)!;
            var target = Path.Combine(parent, "outside");
            if (linkedRoot) Directory.Move(fixture.Root, target);
            else { Directory.CreateDirectory(target); File.WriteAllText(Path.Combine(target, "kept.txt"), "kept"); }
            var before = Snapshot(target);
            var link = linkedRoot ? fixture.Root : Path.Combine(fixture.Root, "redirected");
            using (var make = Process.Start(new ProcessStartInfo("cmd.exe") {
                ArgumentList = { "/c", "mklink", "/J", link, target }, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true })!) {
                make.WaitForExit();
                Require(make.ExitCode == 0, "Fixture junction was not created.");
            }
            try {
                try {
                    FlutterInstalledUpdateInstallation.PruneCompleted(fixture.Installation, () => Registration(fixture, "0.7.1"));
                    throw new Exception("Linked recovery directory was accepted.");
                } catch (IOException) { }
                Require(Directory.Exists(fixture.Root) && before.SequenceEqual(Snapshot(target)) &&
                    Directory.GetDirectories(parent, ".starbridge-retired-update-*").Length == 0,
                    "Linked transaction or its target changed.");
                RequireInstallationUnchanged(fixture);
            } finally { Directory.Delete(link, recursive: false); }
        }
    }
}
