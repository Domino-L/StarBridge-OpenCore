using StarBridge.HostRuntime.Privacy;
using System.Diagnostics;

internal static class CommunityReadJournalRotationTests
{
    internal static readonly (string Name, Func<Task> Test)[] Cases = [
        ("CX-HANGARDIAG journal retains one bounded backup", Rotation),
        ("CX-HANGARDIAG journal rejects reparse destinations", ReparsePoints)
    ];
    private const int Limit = 128 * 1024;
    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "sb-journalrotation-" + Guid.NewGuid().ToString("N"));
        internal string PathFor(string suffix = "") => Path.Combine(Root, "community-read-diagnostics.log" + suffix);
        internal CommunityReadJournal Journal => new(Root);
        public void Dispose() { if (Directory.Exists(Root)) Directory.Delete(Root, true); }
    }
    private static Task Rotation()
    {
        using var fixture = new Fixture();
        fixture.Journal.Record("official-hangar-current-http", "network", 503, 1);
        var evidence = File.ReadAllText(fixture.PathFor());
        for (var i = 0; i < 3000; i++) fixture.Journal.Record("official-hangar-current-http", "ok", 200, 1);
        Check(File.Exists(fixture.PathFor(".1")), "rotation retains a backup");
        Check(new FileInfo(fixture.PathFor()).Length <= Limit && new FileInfo(fixture.PathFor(".1")).Length <= Limit, "both generations stay bounded");
        Check(Directory.GetFiles(fixture.Root).Length == 2, "only one backup is retained after multiple rotations");
        OfficialHangarDiagnosticTests.AssertPrivate(File.ReadAllLines(fixture.PathFor()).Concat(File.ReadAllLines(fixture.PathFor(".1"))));

        // Put a known failure at the beginning of a full generation, then rotate twice.
        File.WriteAllText(fixture.PathFor(), evidence.PadRight(Limit, ' '));
        fixture.Journal.Record("official-hangar-current-http", "ok", 200, 1);
        Check(File.ReadAllText(fixture.PathFor(".1")).StartsWith(evidence, StringComparison.Ordinal), "old failure survives rotation byte for byte");
        Check(File.ReadAllLines(fixture.PathFor()).Single().Contains("code=ok"), "new generation starts with the new record");
        var next = File.ReadAllText(fixture.PathFor());
        File.WriteAllText(fixture.PathFor(), next.PadRight(Limit, ' '));
        fixture.Journal.Record("official-hangar-project", "network", null, 2);
        Check(File.ReadAllText(fixture.PathFor(".1")).StartsWith(next, StringComparison.Ordinal), "next rotation replaces the sole backup");
        return Task.CompletedTask;
    }
    private static Task ReparsePoints()
    {
        using var fixture = new Fixture();
        Directory.CreateDirectory(fixture.Root);
        var target = Path.Combine(fixture.Root, "target");
        Directory.CreateDirectory(target);
        var targetFile = Path.Combine(target, "evidence.txt");
        File.WriteAllText(targetFile, "retained target evidence");
        foreach (var suffix in new[] { "", ".1" })
        {
            var link = fixture.PathFor(suffix);
            var fileLink = CreateLink(link, targetFile, target);
            try {
                if (suffix.Length > 0) File.WriteAllText(fixture.PathFor(), new string(' ', Limit));
                fixture.Journal.Record("official-hangar-project", "network", null, 1);
                Check(File.GetAttributes(link).HasFlag(FileAttributes.ReparsePoint), "journal never replaces reparse destination");
                Check(Directory.GetFileSystemEntries(target).Length == 1 && File.ReadAllText(targetFile) == "retained target evidence", "journal does not follow reparse destination");
                if (suffix.Length > 0) {
                    Check(new FileInfo(fixture.PathFor()).Length == Limit, "backup reparse point blocks rotation without losing active evidence");
                    File.WriteAllText(fixture.PathFor(), "retained active evidence");
                    fixture.Journal.Record("official-hangar-project", "network", null, 1);
                    Check(File.ReadAllText(fixture.PathFor()) == "retained active evidence", "backup reparse point is checked before appending too");
                }
            }
            finally { if (fileLink) File.Delete(link); else Directory.Delete(link); }
        }
        var parentLink = Path.Combine(fixture.Root, "linked-root");
        CreateJunction(parentLink, target);
        try {
            new CommunityReadJournal(parentLink).Record("official-hangar-project", "network", null, 1);
            Check(Directory.GetFileSystemEntries(target).Length == 1, "reparse root and ancestors remain rejected");
        }
        finally { Directory.Delete(parentLink); }
        return Task.CompletedTask;
    }
    private static bool CreateLink(string link, string file, string directory)
    {
        try { File.CreateSymbolicLink(link, file); return true; }
        catch (Exception error) when (error is UnauthorizedAccessException or PlatformNotSupportedException or IOException)
        {
            // Directory junctions exercise the same reparse guard without symlink privilege.
            CreateJunction(link, directory);
            return false;
        }
    }
    private static void CreateJunction(string link, string target)
    {
        var start = new ProcessStartInfo("cmd.exe") { UseShellExecute = false, CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "/d", "/c", "mklink", "/J", link, target }) start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        Console.WriteLine("Owned journal junction helper PID=" + process.Id);
        process.StandardOutput.ReadToEnd(); process.StandardError.ReadToEnd();
        process.WaitForExit();
        Check(process.ExitCode == 0, "local junction creation succeeds");
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
