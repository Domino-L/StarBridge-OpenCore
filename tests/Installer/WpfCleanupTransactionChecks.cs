using System.Security.Cryptography;
using System.Text.Json;

var root = Path.GetFullPath(args.Single());
var count = 0;
void Check(bool value, string name) { if (!value) throw new Exception(name); count++; }
Fixture Make() => new(Path.Combine(root, Guid.NewGuid().ToString("N")));
using (var f = Make()) {
    Check(f.Run() == "committed", "whole retirement committed");
    Check(f.Registry.Current is null && f.Registry.Removals == 1, "old registration retired once");
    Check(!File.Exists(Path.Combine(f.Old, "Star Bridge.exe")) && !File.Exists(Path.Combine(f.Old, "unins000.exe")), "old executables removed from installation");
    Check(File.ReadAllText(Path.Combine(f.Old, "private.dat")) == "keep", "unknown data preserved");
    Check(File.ReadAllText(Path.Combine(f.Data, "account.json")) == "keep", "separate data preserved");
    Check(f.Run() == "committed" && f.Registry.Removals == 1, "completed run never replayed");
    Check(f.Handoffs == 1, "completed recovery does not overwrite newer shell choice");
}
foreach (var phase in new[] { "before-files", "after-files", "after-registration" }) {
    using var f = Make();
    Check(f.Run(p => { if (p == phase) throw new IOException("fixture"); }) == "restored", "failure restored at " + phase);
    Check(File.Exists(Path.Combine(f.Old, "Star Bridge.exe")) && File.Exists(Path.Combine(f.Old, "unins000.dat")), "program and uninstaller restored");
    Check(f.Registry.Current is not null, "registration restored");
    Check(f.Run() == "restored", "failed cleanup not automatically replayed");
}
using (var f = Make()) {
    Check(f.Run(p => { if (p == "after-files") f.Healthy = false; }) == "restored", "new client exit restores old files");
    Check(File.Exists(Path.Combine(f.Old, "Star Bridge.exe")), "health failure retains old executable");
}
using (var f = Make()) {
    f.Healthy = false;
    try { f.Run(); throw new Exception("unhealthy accepted"); } catch (IOException) { count++; }
    Check(f.Registry.Removals == 0 && !File.Exists(Path.Combine(f.Recovery, "cleanup.json")), "no health no intent/mutation");
}
using (var f = Make()) {
    f.ShellOk = false;
    Check(f.Run() == "shell-review-required" && File.Exists(Path.Combine(f.Old, "Star Bridge.exe")), "shell mismatch blocks retirement");
}
using (var f = Make()) {
    File.WriteAllText(Path.Combine(f.Old, "lib.dll"), "modified");
    try { f.Run(); throw new Exception("modified accepted"); } catch (InvalidDataException) { count++; }
    Check(f.Registry.Removals == 0 && f.Handoffs == 0, "modified known file blocks before shell writes");
}
using (var f = Make()) {
    Check(f.Run(p => { if (p == "after-files") {
        File.WriteAllText(Path.Combine(f.Old, "Star Bridge.exe"), "concurrent-user-file");
        throw new IOException();
    } }) == "needs-review", "conflicting file retained");
    Check(File.ReadAllText(Path.Combine(f.Old, "Star Bridge.exe")) == "concurrent-user-file", "never overwrite concurrent file");
    Check(File.Exists(Path.Combine(f.Recovery, "files", "program", "Star Bridge.exe")), "original remains recoverable");
}
foreach (var phase in new[] { "moving", "files-quarantined" }) {
    using var f = Make();
    Check(f.Run() == "committed", "prepare interruption fixture");
    var path = Path.Combine(f.Recovery, "cleanup.json");
    var journal = JsonSerializer.Deserialize<WpfCleanupJournal>(File.ReadAllBytes(path), WpfCleanupFiles.Json)!;
    File.WriteAllBytes(path, JsonSerializer.SerializeToUtf8Bytes(journal with { Phase = phase }, WpfCleanupFiles.Json));
    Check(f.Run() == "restored", "fresh transaction recovers durable phase " + phase);
    Check(f.Registry.Current is not null && File.Exists(Path.Combine(f.Old, "Star Bridge.exe")), "crash recovery restores files and registry");
}
using (var f = Make()) {
    f.Run();
    var path = Path.Combine(f.Recovery, "cleanup.json");
    var journal = JsonSerializer.Deserialize<WpfCleanupJournal>(File.ReadAllBytes(path), WpfCleanupFiles.Json)!;
    File.WriteAllBytes(path, JsonSerializer.SerializeToUtf8Bytes(journal with {
        Phase = "moving", InstallerFiles = [journal.InstallerFiles[0] with { Path = "private.dat" }, journal.InstallerFiles[1]]
    }, WpfCleanupFiles.Json));
    try { f.Run(); throw new Exception("tampered artifact accepted"); } catch (InvalidDataException) { count++; }
    Check(f.Registry.Current is null, "invalid journal cannot restore registration");
}
Console.WriteLine($"PASS: {count} legacy cleanup transaction checks; inert files and memory registration only.");

sealed class MemoryRegistration : IWpfCleanupRegistration
{
    internal WpfCleanupRegistrationRecord? Current;
    internal int Removals;
    public WpfCleanupRegistrationRecord? Read() => Current;
    public void RemoveIfUnchanged(WpfCleanupRegistrationRecord expected) {
        if (Current is null || !WpfCleanupTransaction.Equivalent(Current, expected)) throw new IOException();
        Current = null; Removals++;
    }
    public bool RestoreIfAbsent(WpfCleanupRegistrationRecord expected) {
        if (Current is not null) return WpfCleanupTransaction.Equivalent(Current, expected);
        Current = expected; return true;
    }
}
sealed class Fixture : IDisposable
{
    internal readonly string Old, New, Data, Recovery;
    internal readonly MemoryRegistration Registry = new();
    internal readonly WpfCleanupCatalog Catalog;
    internal bool Healthy = true, ShellOk = true;
    internal int Handoffs;
    internal Fixture(string root) {
        Old = Path.Combine(root, "old"); New = Path.Combine(root, "new");
        Data = Path.Combine(root, "data"); Recovery = Path.Combine(root, "recovery");
        foreach (var dir in new[] { Old, New, Data, Recovery }) Directory.CreateDirectory(dir);
        foreach (var name in new[] { "Star Bridge.exe", "lib.dll", "unins000.exe", "unins000.dat" }) File.WriteAllText(Path.Combine(Old, name), "inert-" + name);
        File.WriteAllText(Path.Combine(Old, "private.dat"), "keep");
        File.WriteAllText(Path.Combine(Data, "account.json"), "keep");
        Catalog = new("0.6.6.1", new string('0', 64), new[] { "Star Bridge.exe", "lib.dll" }.Select(name => {
            var bytes = File.ReadAllBytes(Path.Combine(Old, name));
            return new WpfCleanupFile(name, bytes.Length, Convert.ToHexString(SHA256.HashData(bytes)));
        }).ToArray());
        Registry.Current = new(Old, [new("fixture", 1, ["fixed"]) ]);
    }
    internal string Run(Action<string>? checkpoint = null) => new WpfCleanupTransaction(Registry,
        () => { }, () => Healthy, () => { Handoffs++; return ShellOk; }).Run(Catalog, Old, New, [Data], Recovery, checkpoint);
    public void Dispose() { } // Retain scoped artifacts as evidence; no broad deletes.
}
