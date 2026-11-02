using System.Security.Cryptography;
using System.Text;
using StarBridge.HostRuntime.Communities;
using static OfficialFleetAnnouncementManagementClientTests;

internal static class OfficialFleetAnnouncementRecoveryTests
{
    internal static async Task RunAsync()
    {
        await ProtectedRoundTripAsync();
        await FullAndTerminalAsync();
        await FailureBeforePostAsync();
    }
    private static AnnouncementJournalRecord Record(string account, Uri origin, string id, DateTimeOffset now)
    {
        var intent = new AnnouncementJournalIntent("officialFleet:7", new string('a', 64), new string('b', 64),
            "publish", 3, 1, null, null, "Synthetic title", "Synthetic body");
        return new(id, AnnouncementAttemptJournal.OperationId(account, origin, id), intent,
            AnnouncementAttemptJournal.Fingerprint(intent), new string('c', 64), now, "prepared");
    }
    private static async Task ProtectedRoundTripAsync()
    {
        var root = Path.Combine(Path.GetTempPath(), "a4b-dpapi-" + Guid.NewGuid().ToString("N"));
        var clock = new Clock(DateTimeOffset.UtcNow); var journal = new AnnouncementAttemptJournal(root, clock);
        var row = Record(Driver.Account, Driver.Origin, new string('a', 32), clock.GetUtcNow());
        await journal.RunAsync(Driver.Account, Driver.Origin, async session =>
        {
            Check(session.Items.Length == 0, "A new local recovery partition is known empty without inventing any Server outcome");
            await session.SaveAsync(row); await session.SaveAsync(row with { Phase = "sendStarted" });
            return 0;
        }, () => { }, default);
        var path = Directory.GetFiles(root, "*.dat").Single(); var encrypted = await File.ReadAllBytesAsync(path);
        Check(!Encoding.UTF8.GetString(encrypted).Contains("Synthetic body", StringComparison.Ordinal),
            "Actual Windows DPAPI journal does not persist plaintext announcement content");
        var recreated = new AnnouncementAttemptJournal(root, clock);
        await recreated.RunAsync(Driver.Account, Driver.Origin, async session =>
        {
            var restored = session.Find(row.RequestId)!;
            Check(restored.Phase == "sendStarted" && restored.OperationId == row.OperationId, "Reconstructed journal retains the original uncertain operation");
            var changed = restored with { Intent = restored.Intent with { Title = "Different" } };
            try { await session.SaveAsync(changed); throw new Exception("Expected immutable intent refusal"); }
            catch (InvalidDataException) { }
            Check(session.Find(row.RequestId) == restored, "Rejected immutable intent change leaves in-memory recovery record unchanged");
            await Task.CompletedTask; return 0;
        }, () => { }, default);
        var alternate = Path.Combine(root, AnnouncementAttemptJournal.Partition("another-account", Driver.Origin) + ".dat");
        File.Copy(path, alternate);
        try { await recreated.RunAsync("another-account", Driver.Origin, _ => Task.FromResult(0), () => { }, default); throw new Exception("Expected partition refusal"); }
        catch (Exception error) when (error is CryptographicException or InvalidDataException)
        { Check(true, "Copied ciphertext cannot be read as another authenticated account partition"); }
        var otherOrigin = new Uri("https://other-announcement.invalid/");
        File.Copy(path, Path.Combine(root, AnnouncementAttemptJournal.Partition(Driver.Account, otherOrigin) + ".dat"));
        try { await recreated.RunAsync(Driver.Account, otherOrigin, _ => Task.FromResult(0), () => { }, default); throw new Exception("Expected origin refusal"); }
        catch (Exception error) when (error is CryptographicException or InvalidDataException)
        { Check(true, "Copied ciphertext cannot be rebound to another trusted origin"); }
        encrypted[encrypted.Length / 2] ^= 127; await File.WriteAllBytesAsync(path, encrypted);
        try { await recreated.RunAsync(Driver.Account, Driver.Origin, _ => Task.FromResult(0), () => { }, default); throw new Exception("Expected corruption refusal"); }
        catch (Exception error) when (error is CryptographicException or InvalidDataException)
        { Check(true, "Corrupt protected state is unavailable, never quietly known empty"); }
    }
    private static async Task FullAndTerminalAsync()
    {
        var now = DateTimeOffset.UtcNow; var clock = new Clock(now);
        var root = Path.Combine(Path.GetTempPath(), "a4b-full-" + Guid.NewGuid().ToString("N"));
        var journal = new AnnouncementAttemptJournal(root, clock);
        await journal.RunAsync(Driver.Account, Driver.Origin, async session =>
        {
            for (var i = 0; i < 128; i++) await session.SaveAsync(Record(Driver.Account, Driver.Origin, i.ToString("x32"), now));
            try { await session.SaveAsync(Record(Driver.Account, Driver.Origin, new string('f', 32), now)); throw new Exception("Expected unresolved-capacity refusal"); }
            catch (InvalidDataException) { }
            Check(session.Items.Length == 128 && session.Find(new string('f', 32)) is null,
                "128 unresolved records refuse a new request without deleting uncertainty");
            return 0;
        }, () => { }, default);
        using var scene = new Driver(root: root);
        var result = await scene.Send(scene.Intent(await scene.Open(), new string('e', 32)));
        Check(Status(result) == "rejected" && scene.Handler.Posts == 0,
            "A full unresolved real protected journal prevents positive HTTP before it starts");
        var lockRoot = Path.Combine(Path.GetTempPath(), "a4b-lock-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(lockRoot);
        using var lease = new FileStream(Path.Combine(lockRoot, AnnouncementAttemptJournal.Partition(Driver.Account, Driver.Origin) + ".dat.lock"),
            FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        using var locked = new Driver(root: lockRoot);
        Check(Status(await locked.Send(locked.Intent(await locked.Open(), Guid.NewGuid().ToString("N")))) == "rejected" && locked.Handler.Posts == 0,
            "A real cross-process-style exclusive file lock never permits an unlocked POST");
    }
    private static async Task FailureBeforePostAsync()
    {
        foreach (var phase in new[] { "prepared", "sendStarted" })
        {
            using var scene = new Driver(p => { if (p == phase) throw new IOException("Synthetic before-replace " + phase); });
            var result = await scene.Send(scene.Intent(await scene.Open(), Guid.NewGuid().ToString("N")));
            Check((Status(result) is "rejected" or "unknown") && scene.Handler.Posts == 0,
                "Explicit " + phase + " IO failpoint is not mistaken for a durable preparation or a sent POST");
        }
        using var acknowledged = new Driver(p => { if (p == "accepted") throw new IOException("Synthetic local acknowledgement persistence failure"); });
        var body = acknowledged.Intent(await acknowledged.Open(), Guid.NewGuid().ToString("N"));
        Check(Status(await acknowledged.Send(body)) == "unknown" && acknowledged.Handler.Posts == 1,
            "Post-success local acknowledgement failure retains uncertainty rather than false durable success");
        Check(Status(await acknowledged.Send(body)) == "unknown" && acknowledged.Handler.Posts == 1,
            "Unacknowledged original attempt is not sent again after local persistence failure");
    }
}
