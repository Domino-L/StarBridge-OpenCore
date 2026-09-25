using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

var root = args[0];
var checks = 0;
void Check(bool ok, string name) { if (!ok) throw new Exception(name); checks++; Console.WriteLine("PASS " + name); }
void Reject(Action operation, string name) {
    try { operation(); } catch (Exception e) when (e is InvalidDataException or IOException) { Check(true, name); return; }
    throw new Exception("Unexpected acceptance: " + name);
}
string Dir(string path) => Directory.CreateDirectory(path).FullName;
WpfCleanupFile Entry(string path, string text) => new(path, Encoding.UTF8.GetByteCount(text),
    Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant());
var files = new[] { Entry("Star Bridge.exe", "inert executable fixture"), Entry("lib/module.dll", "inert module fixture") };
var catalog = new WpfCleanupCatalog("0.6.6.1", new string('a', 64), files);
(string Old, string App, string Data, string Backup) Fixture(string name) {
    var basePath = Dir(Path.Combine(root, name));
    var old = Dir(Path.Combine(basePath, "old")); var app = Dir(Path.Combine(basePath, "new"));
    var data = Dir(Path.Combine(basePath, "data")); var backup = Dir(Path.Combine(basePath, "backup"));
    Dir(Path.Combine(old, "lib"));
    File.WriteAllText(Path.Combine(old, "Star Bridge.exe"), "inert executable fixture");
    File.WriteAllText(Path.Combine(old, "lib/module.dll"), "inert module fixture");
    File.WriteAllText(Path.Combine(old, "user-notes.txt"), "unknown user file");
    File.WriteAllText(Path.Combine(old, "unins000.dat"), "untrusted uninstall instructions - never execute");
    File.WriteAllText(Path.Combine(data, "account-sentinel"), "private fixture");
    File.WriteAllText(Path.Combine(app, "new-sentinel"), "new fixture");
    return (old, app, data, backup);
}
var f = Fixture("success");
var plan = WpfCleanupFiles.Prepare(catalog, f.Old, f.App, f.Data);
Check(plan.Files.Length == 2 && File.Exists(Path.Combine(f.Old, "Star Bridge.exe")), "preparation is read-only and includes only reviewed files");
var result = WpfCleanupFiles.Quarantine(plan, f.Backup);
Check(result == new WpfCleanupFileResult("quarantined", 2), "known files quarantined without invoking an uninstaller");
Check(!File.Exists(Path.Combine(f.Old, "Star Bridge.exe")) && File.Exists(Path.Combine(f.Backup, "program/Star Bridge.exe")), "old executable removed from original path but recoverable");
Check(File.ReadAllText(Path.Combine(f.Old, "user-notes.txt")) == "unknown user file" &&
    File.Exists(Path.Combine(f.Old, "unins000.dat")), "unknown files and uninstall instructions untouched");
Check(File.ReadAllText(Path.Combine(f.Data, "account-sentinel")) == "private fixture" &&
    File.ReadAllText(Path.Combine(f.App, "new-sentinel")) == "new fixture", "new application and user data unchanged");
var recovery = WpfCleanupFiles.ReadRecovery(catalog, f.Old, f.App, [f.Data], f.Backup);
Check(WpfCleanupFiles.Restore(recovery, f.Backup) && File.Exists(Path.Combine(f.Old, "Star Bridge.exe")), "interrupted coordinator can restore trusted files from persisted plan");
Reject(() => WpfCleanupFiles.Quarantine(plan, f.Backup), "existing recovery directory prevents replay");
Reject(() => WpfCleanupFiles.ReadRecovery(catalog, f.Old, f.Data, [f.App], f.Backup), "changed recovery identity rejected");

f = Fixture("modified");
File.WriteAllText(Path.Combine(f.Old, "lib/module.dll"), "user modified file");
Reject(() => WpfCleanupFiles.Prepare(catalog, f.Old, f.App, f.Data), "modified known file rejects entire plan");
Check(File.Exists(Path.Combine(f.Old, "Star Bridge.exe")), "preflight failure leaves old client intact");
f = Fixture("overlap");
Reject(() => WpfCleanupFiles.Prepare(catalog, f.Old, f.App, f.Old), "data inside old installation blocked");
Reject(() => WpfCleanupFiles.Prepare(catalog, f.Old, f.Old, f.Data), "new and old installation overlap blocked");
Reject(() => WpfCleanupFiles.Prepare(catalog, f.Old, f.App), "unknown data roots blocked");
Reject(() => WpfCleanupFiles.Prepare(catalog, Path.GetPathRoot(f.Old)!, f.App, f.Data), "drive root never treated as installation");
File.WriteAllText(Path.Combine(f.Old, "StarBridge.sln"), "source checkout");
Reject(() => WpfCleanupFiles.Prepare(catalog, f.Old, f.App, f.Data), "source checkout rejected");
f = Fixture("missing-main"); File.Delete(Path.Combine(f.Old, "Star Bridge.exe"));
Reject(() => WpfCleanupFiles.Prepare(catalog, f.Old, f.App, f.Data), "main executable identity required");
f = Fixture("invalid-catalog");
foreach (var path in new[] { "../escape", "sub/../../escape", "C:/escape", "a:stream", "foo./bar", "/absolute", "sub//file" })
    Reject(() => WpfCleanupFiles.Prepare(catalog with { Files = [.. files, Entry(path, "x")] }, f.Old, f.App, f.Data), "invalid catalog path rejected: " + path);
Reject(() => WpfCleanupFiles.Prepare(catalog with { Files = [.. files, files[0] with { Path = "STAR BRIDGE.EXE" }] }, f.Old, f.App, f.Data), "case insensitive duplicate rejected");

f = Fixture("failure"); plan = WpfCleanupFiles.Prepare(catalog, f.Old, f.App, f.Data);
result = WpfCleanupFiles.Quarantine(plan, f.Backup, count => { if (count == 1) throw new IOException("injected move failure"); });
Check(result.State == "restored" && File.Exists(Path.Combine(f.Old, "Star Bridge.exe")) &&
    File.Exists(Path.Combine(f.Old, "lib/module.dll")), "partial move failure restores usable old payload");
f = Fixture("concurrent-edit"); plan = WpfCleanupFiles.Prepare(catalog, f.Old, f.App, f.Data);
result = WpfCleanupFiles.Quarantine(plan, f.Backup, count => {
    if (count == 1) { File.WriteAllText(Path.Combine(f.Old, "Star Bridge.exe"), "concurrent replacement"); throw new IOException(); }
});
Check(result.State == "needs-review" && File.ReadAllText(Path.Combine(f.Old, "Star Bridge.exe")) == "concurrent replacement" &&
    File.Exists(Path.Combine(f.Backup, "program/Star Bridge.exe")), "rollback preserves concurrent replacement and original backup");
f = Fixture("changed-after-plan"); plan = WpfCleanupFiles.Prepare(catalog, f.Old, f.App, f.Data);
File.WriteAllText(Path.Combine(f.Old, "Star Bridge.exe"), "changed after preparation");
result = WpfCleanupFiles.Quarantine(plan, f.Backup);
Check(result.State == "needs-review" && result.QuarantinedFiles == 0 &&
    File.ReadAllText(Path.Combine(f.Old, "Star Bridge.exe")) == "changed after preparation", "fresh hash check blocks changed source");
f = Fixture("junction");
File.Delete(Path.Combine(f.Data, "module.dll")); // Test setup wrote only this inert fixture file through the junction.
Reject(() => WpfCleanupFiles.Prepare(catalog, f.Old, f.App, f.Data), "junction ancestor rejected even when expected file is absent");
f = Fixture("backup-overlap"); plan = WpfCleanupFiles.Prepare(catalog, f.Old, f.App, f.Data);
Reject(() => WpfCleanupFiles.Quarantine(plan, f.Data), "backup never uses protected data root");

var release = WpfCleanupCatalog.Released0661();
Check(release.Version == "0.6.6.1" && release.Files.Length >= 500 && release.Files.Any(x => x.Path == "Star Bridge.exe"), "real release inventory embedded and version pinned");
f = Fixture("corrupt-recovery"); plan = WpfCleanupFiles.Prepare(catalog, f.Old, f.App, f.Data);
result = WpfCleanupFiles.Quarantine(plan, f.Backup);
var record = Path.Combine(f.Backup, "files.json");
File.WriteAllText(record, JsonSerializer.Serialize(plan with { Files = [.. files, Entry("../escape", "x")] }, WpfCleanupFiles.Json));
Reject(() => WpfCleanupFiles.ReadRecovery(catalog, f.Old, f.App, [f.Data], f.Backup), "journal cannot add unapproved deletion or restoration paths");
File.WriteAllText(record, JsonSerializer.Serialize(plan with { Files = [files[0] with { Sha256 = new string('a', 64) }] }, WpfCleanupFiles.Json));
Reject(() => WpfCleanupFiles.ReadRecovery(catalog, f.Old, f.App, [f.Data], f.Backup), "journal cannot promote locally invented fingerprints");
if (args.Length == 2) {
    f = Fixture("real-release-read-only");
    var real = WpfCleanupFiles.Prepare(release, args[1], f.App, f.Data);
    Check(real.Files.Length == release.Files.Length, "all real published payload hashes match embedded cleanup inventory (read-only)");
}
Console.WriteLine($"{checks} cleanup file checks passed. Inert fixtures only; no user installation or registry changed.");
