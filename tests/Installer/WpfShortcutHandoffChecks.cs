using System.Security.Cryptography;
using Handoff = WpfShortcutHandoff;

var root = args.Single();
var links = Path.Combine(root, "links");
var old = Directory.CreateDirectory(Path.Combine(root, "old")).FullName;
var app = Directory.CreateDirectory(Path.Combine(root, "new")).FullName;
var oldExe = Path.Combine(old, "Star Bridge.exe");
var newExe = Path.Combine(app, "starbridge_flutter.exe");
var recovery = Path.Combine(root, "recovery");
foreach (var file in new[] { oldExe, newExe, Path.Combine(old, "unins000.exe"), Path.Combine(old, "unins000.dat") })
    File.WriteAllText(file, "Inert fixture, never execute.");
int checks = 0;
void Check(bool condition, string name) { if (!condition) throw new Exception(name); Console.WriteLine("PASS " + name); checks++; }
string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
string Make(string name, string? target = null, string arguments = "")
{
    var path = Path.Combine(links, name + ".lnk");
    Handoff.WriteShortcut(path, new(target ?? oldExe, arguments, old, oldExe + ",0"));
    return path;
}
bool Move(string path, Action<string, string>? replace = null) =>
    Handoff.TryOne(path, oldExe, newExe, Handoff.ReadShortcut, Handoff.WriteShortcut, replace, recovery);
string Archived(string path, string hash) => Handoff.RecoveryBackupPath(recovery, path, hash);
var path = Make("owned"); var hash = Hash(path);
Check(Move(path) && Handoff.ReadShortcut(path).Target == newExe, "verified link opens new app");
Check(Hash(Archived(path, hash)) == hash, "original bytes retained outside shell folders");
Check(!File.Exists(path + ".starbridge-wpf-backup"), "successful handoff leaves no visible backup beside shortcut");
Check(Move(path), "repeat after success is harmless");
path = Make("new-target-old-icon");
Handoff.WriteShortcut(path, new(newExe, "", old, oldExe + ",0"));
hash = Hash(path);
Check(Move(path) && Handoff.ReadShortcut(path).Icon == newExe + ",0" &&
    Handoff.ReadShortcut(path).WorkingDirectory == app,
    "already migrated target replaces inherited legacy icon and working directory");
Check(Hash(Archived(path, hash)) == hash, "inherited icon repair retains original shortcut bytes");
Check(Move(path), "inherited icon repair is idempotent");
path = Make("new-target-custom-icon");
Handoff.WriteShortcut(path, new(newExe, "", app, Path.Combine(old, "custom.ico") + ",0"));
hash = Hash(path);
Check(Move(path) && Hash(path) == hash, "user selected icon on new shortcut is preserved");
path = Make("icon-repair-retry");
Handoff.WriteShortcut(path, new(newExe, "", old, oldExe + ",0"));
hash = Hash(path);
Check(!Move(path, (_, _) => throw new IOException("Fixture sharing violation")) && Hash(path) == hash,
    "failed inherited icon replacement preserves original link");
Check(Move(path) && Handoff.ReadShortcut(path).Icon == newExe + ",0" && Hash(Archived(path, hash)) == hash,
    "inherited icon replacement resumes from verified stage and backup");
path = Make("icon-archive-retry");
Handoff.WriteShortcut(path, new(newExe, "", old, oldExe + ",0"));
hash = Hash(path);
File.Copy(path, path + ".starbridge-icon-backup");
Handoff.WriteShortcut(path, new(newExe, "", app, newExe + ",0"));
Check(Move(path) && Hash(Archived(path, hash)) == hash && !File.Exists(path + ".starbridge-icon-backup"),
    "completed icon replacement resumes interrupted archive without rewriting link");
path = Make("icon-backup-conflict");
Handoff.WriteShortcut(path, new(newExe, "", old, oldExe + ",0"));
hash = Hash(path);
File.WriteAllText(path + ".starbridge-icon-backup", "foreign backup");
Check(!Move(path) && Hash(path) == hash, "foreign icon backup blocks replacement");
path = Make("icon-custom-working-directory");
Handoff.WriteShortcut(path, new(newExe, "", recovery, oldExe + ",0"));
hash = Hash(path);
Check(Move(path) && Hash(path) == hash, "custom working directory on new shortcut is preserved");
path = Make("previous-release"); hash = Hash(path);
File.Copy(path, path + ".starbridge-wpf-backup");
Handoff.WriteShortcut(path, new(newExe, "", app, newExe + ",0"));
var newHash = Hash(path);
Check(Move(path) && Hash(path) == newHash && Hash(Archived(path, hash)) == hash &&
    !File.Exists(path + ".starbridge-wpf-backup"), "already handed-off link archives previous release backup without rewriting link");
path = Make("archive-conflict"); hash = Hash(path);
File.Copy(path, path + ".starbridge-wpf-backup");
Handoff.WriteShortcut(path, new(newExe, "", app, newExe + ",0"));
File.WriteAllText(Archived(path, hash), "foreign archive");
Check(!Move(path) && Hash(path + ".starbridge-wpf-backup") == hash &&
    File.ReadAllText(Archived(path, hash)) == "foreign archive", "archive conflict preserves both copies");
path = Make("archive-resume"); hash = Hash(path);
File.Copy(path, path + ".starbridge-wpf-backup");
File.Copy(path, Archived(path, hash));
Handoff.WriteShortcut(path, new(newExe, "", app, newExe + ",0"));
Check(Move(path) && !File.Exists(path + ".starbridge-wpf-backup") && Hash(Archived(path, hash)) == hash,
    "interrupted archive resumes from byte-identical copy");
path = Make("archive-foreign-backup");
Handoff.WriteShortcut(path + ".starbridge-wpf-backup", new(oldExe, "--custom", old, oldExe));
Handoff.WriteShortcut(path, new(newExe, "", app, newExe));
Check(!Move(path) && File.Exists(path + ".starbridge-wpf-backup"), "custom backup beside new link is untouched");
path = Make("archive-link-edited"); hash = Hash(path);
File.Copy(path, path + ".starbridge-wpf-backup");
Handoff.WriteShortcut(path, new(newExe, "", app, newExe));
ShortcutData ReadWithEdit(string candidate) {
    var link = Handoff.ReadShortcut(candidate);
    if (candidate.EndsWith(".starbridge-wpf-backup", StringComparison.Ordinal))
        Handoff.WriteShortcut(path, new(newExe, "--user-edit", app, newExe));
    return link;
}
Check(!Handoff.TryOne(path, oldExe, newExe, ReadWithEdit, Handoff.WriteShortcut, recoveryRoot: recovery) &&
    Hash(path + ".starbridge-wpf-backup") == hash && Handoff.ReadShortcut(path).Arguments == "--user-edit",
    "link edited during archival preserves backup and user edit");
path = Make("archive-junction"); hash = Hash(path);
File.Copy(path, path + ".starbridge-wpf-backup");
Handoff.WriteShortcut(path, new(newExe, "", app, newExe));
Check(!Handoff.TryOne(path, oldExe, newExe, Handoff.ReadShortcut, Handoff.WriteShortcut,
    recoveryRoot: Path.Combine(root, "redirected", "archive")) && Hash(path + ".starbridge-wpf-backup") == hash,
    "recovery junction is rejected without removing backup");
path = Make("foreign", Path.Combine(old, "foreign.exe")); hash = Hash(path);
Check(!Move(path) && Hash(path) == hash, "foreign target unchanged");
path = Make("custom", arguments: "--custom"); hash = Hash(path);
Check(!Move(path) && Hash(path) == hash, "custom arguments unchanged");
path = Path.Combine(links, "absent.lnk");
Check(Move(path) && !File.Exists(path), "deleted optional icon stays absent");
path = Make("backup-conflict"); hash = Hash(path); File.WriteAllText(path + ".starbridge-wpf-backup", "foreign backup");
Check(!Move(path) && Hash(path) == hash, "foreign backup blocks overwrite");
path = Make("stage-conflict"); hash = Hash(path); Handoff.WriteShortcut(path + ".starbridge-new.lnk", new(oldExe, "--foreign", old, oldExe));
Check(!Move(path) && Hash(path) == hash, "foreign staging file blocks overwrite");
path = Make("retry"); hash = Hash(path);
Check(!Move(path, (_, _) => throw new IOException("Fixture sharing violation")) && Hash(path) == hash && Hash(path + ".starbridge-wpf-backup") == hash,
    "failed replace preserves original and backup");
Check(Move(path) && Handoff.ReadShortcut(path).Target == newExe, "retry reuses verified backup and stage");
path = Make("backup-only"); hash = Hash(path); File.Copy(path, path + ".starbridge-wpf-backup");
Check(Move(path) && Hash(Archived(path, hash)) == hash, "resume after backup before staging");
path = Make("edited-after-failure"); Move(path, (_, _) => throw new IOException());
Handoff.WriteShortcut(path, new(oldExe, "--changed", old, oldExe)); hash = Hash(path);
Check(!Move(path) && Hash(path) == hash, "user edit after failure is preserved");
Check(!Handoff.PlainPath(Path.Combine(root, "redirected")), "junction rejected");
Check(!Handoff.PlainPath(links + @"\..\old"), "noncanonical path rejected");
var registration = new LegacyRegistration("current-user", old, '"' + Path.Combine(old, "unins000.exe") + '"');
bool Run(params LegacyRegistration[] registrations) => Handoff.Run(registrations, newExe, links, links, Handoff.ReadShortcut, Handoff.WriteShortcut, recovery);
Check(Run(), "no old registration no action");
Check(!Run(registration with { Scope = "all-users" }), "machine installation untouched");
Check(!Run(registration, registration with { Directory = app }), "conflicting registrations rejected");
Check(!Run(registration with { Uninstall = "unverified" }), "uninstaller identity mismatch rejected");
path = Make("星海舰桥");
Check(Run(registration) && Handoff.ReadShortcut(path).Target == newExe, "registered known desktop path connected");
var menu = Directory.CreateDirectory(Path.Combine(links, "星海舰桥")).FullName;
var menuLink = Path.Combine(menu, "星海舰桥.lnk");
Handoff.WriteShortcut(menuLink, new(oldExe, "", old, oldExe + ",0"));
Check(Run(registration) && Handoff.ReadShortcut(menuLink).Target == newExe, "registered known start menu path connected");
File.Delete(Path.Combine(old, "unins000.dat"));
Check(!Run(registration), "damaged registration payload blocks handoff");
Console.WriteLine($"{checks} shared shortcut handoff checks passed.");
