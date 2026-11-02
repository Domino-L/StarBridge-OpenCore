using System.Diagnostics;
using System.Net;
using System.Security.AccessControl;
using System.Text;
using StarBridge.HostRuntime.Auth;

// 2026-10-31: the lease failed at once when contended, and File.Replace exposed a
// gap to lease-free readers. Both surfaced as a flaky "file in use" Host failure.
internal static class WindowsTokenVaultConcurrencyTests
{
    private const string Key = "synthetic-scm:subject";

    internal static async Task Verify()
    {
        await InTemporaryRoot(ContendedLeaseWaitsItsTurn);
        await InTemporaryRoot(StuckLeaseStillFailsWithoutChange);
        await InTemporaryRoot(TwoInstancesKeepEveryWrite);
        await InTemporaryRoot(LeaseFreeReaderNeverSeesAGap);
        await InTemporaryRoot(CommitWaitsForAReaderWithoutDeleteShare);
        await InTemporaryRoot(StuckReaderFailsCommitWithoutChange);
        await InTemporaryRoot(LostOwnershipStopsAWaitingCommit);
        await InTemporaryRoot(RotationSurvivesAContendedLease);
        await InTemporaryRoot(CommitKeepsATightenedDacl);
        await InTemporaryRoot(OutsideChangeDuringAWaitStopsTheCommit);
    }

    private static async Task InTemporaryRoot(Func<string, Task> test)
    {
        var root = Directory.CreateTempSubdirectory("starbridge-vault-concurrency-").FullName;
        try { await test(Path.Combine(root, "synthetic-vault.json")); }
        finally { try { Directory.Delete(root, true); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    }

    private static FileStream HoldLease(string path) =>
        new(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);

    // A dedicated thread: a starved thread pool must not outlast the wait budget.
    private static Thread After(int milliseconds, Action action)
    {
        var thread = new Thread(() => { Thread.Sleep(milliseconds); action(); }) { IsBackground = true };
        thread.Start();
        return thread;
    }

    private static void Check(bool condition, string failure)
    {
        if (!condition) throw new InvalidOperationException(failure);
    }

    private static Task ContendedLeaseWaitsItsTurn(string path)
    {
        var vault = new WindowsTokenVault(path);
        vault.SaveRefreshToken(Key, "synthetic-first");
        var lease = HoldLease(path);
        var release = After(300, lease.Dispose);
        new WindowsTokenVault(path).SaveRefreshToken(Key, "synthetic-second");
        release.Join();
        Check(vault.LoadRefreshToken(Key) == "synthetic-second", "A briefly held lease lost the write.");
        Console.WriteLine("PASS Windows vault writer waits for a briefly held lease");
        return Task.CompletedTask;
    }

    private static Task StuckLeaseStillFailsWithoutChange(string path)
    {
        var vault = new WindowsTokenVault(path);
        vault.SaveRefreshToken(Key, "synthetic-first");
        var bytes = File.ReadAllBytes(path);
        using var lease = HoldLease(path);
        var waited = Stopwatch.StartNew();
        try
        {
            vault.SaveRefreshToken(Key, "synthetic-second");
            throw new InvalidOperationException("A stuck lease allowed a second writer.");
        }
        catch (IOException error) when ((error.HResult & 0xFFFF) == 32) { }
        Check(waited.Elapsed < TimeSpan.FromSeconds(30), "A stuck lease blocked its writer without bound.");
        Check(bytes.AsSpan().SequenceEqual(File.ReadAllBytes(path)), "A refused writer changed the vault.");
        Check(Directory.GetFiles(Path.GetDirectoryName(path)!, "*.tmp").Length == 0, "A refused writer left a temporary file.");
        Console.WriteLine("PASS Windows vault stuck lease stays a bounded storage failure");
        return Task.CompletedTask;
    }

    private static Task TwoInstancesKeepEveryWrite(string path)
    {
        new WindowsTokenVault(path).SaveRefreshToken(Key, "synthetic-first");
        var errors = new List<Exception>();
        var writers = Enumerable.Range(0, 2).Select(index => new Thread(() =>
        {
            var vault = new WindowsTokenVault(path);
            try
            {
                for (var write = 0; write < 40; write++)
                    vault.SaveRefreshToken($"{Key}-{index}-{write}", "synthetic-written");
            }
            catch (Exception error) { lock (errors) errors.Add(error); }
        })).ToArray();
        foreach (var writer in writers) writer.Start();
        foreach (var writer in writers) writer.Join();
        if (errors.Count != 0) throw new InvalidOperationException("Concurrent vault writers failed: " + errors[0]);
        var reader = new WindowsTokenVault(path);
        for (var index = 0; index < 2; index++)
            for (var write = 0; write < 40; write++)
                Check(reader.LoadRefreshToken($"{Key}-{index}-{write}") == "synthetic-written", "Concurrent writers lost an entry.");
        Console.WriteLine("PASS Windows vault concurrent instances keep every write");
        return Task.CompletedTask;
    }

    private static Task LeaseFreeReaderNeverSeesAGap(string path)
    {
        var vault = new WindowsTokenVault(path);
        vault.SaveRefreshToken(Key, "synthetic-0");
        var done = false;
        var reads = 0L;
        using var reading = new CountdownEvent(3);
        var errors = new List<string>();
        var readers = Enumerable.Range(0, 3).Select(_ => new Thread(() =>
        {
            var reader = new WindowsTokenVault(path);
            var first = true;
            while (!Volatile.Read(ref done))
            {
                try
                {
                    if (reader.LoadRefreshToken(Key) is null || reader.LoadActiveAccountKey() != Key)
                        lock (errors) errors.Add("A commit made a stored credential look absent.");
                }
                catch (Exception error) { lock (errors) errors.Add(error.Message); }
                Interlocked.Increment(ref reads);
                if (first) { first = false; reading.Signal(); }
            }
        })).ToArray();
        foreach (var reader in readers) reader.Start();
        reading.Wait();
        var readsBefore = Interlocked.Read(ref reads);
        try
        {
            for (var commit = 1; commit <= 80; commit++) vault.SaveRefreshToken(Key, "synthetic-" + commit);
        }
        finally
        {
            Volatile.Write(ref done, true);
            foreach (var reader in readers) reader.Join();
        }
        Check(Interlocked.Read(ref reads) > readsBefore, "Readers did not overlap the commits.");
        if (errors.Count != 0) throw new InvalidOperationException($"{errors.Count} reads failed during commits, first: {errors[0]}");
        Console.WriteLine("PASS Windows vault lease-free reader never sees a commit gap");
        return Task.CompletedTask;
    }

    private static Task CommitWaitsForAReaderWithoutDeleteShare(string path)
    {
        var vault = new WindowsTokenVault(path);
        vault.SaveRefreshToken(Key, "synthetic-first");
        var holder = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        var release = After(300, holder.Dispose);
        vault.SaveRefreshToken(Key, "synthetic-second");
        release.Join();
        Check(vault.LoadRefreshToken(Key) == "synthetic-second", "A briefly open vault lost the commit.");
        Console.WriteLine("PASS Windows vault commit waits for a briefly open vault file");
        return Task.CompletedTask;
    }

    private static Task StuckReaderFailsCommitWithoutChange(string path)
    {
        var vault = new WindowsTokenVault(path);
        vault.SaveRefreshToken(Key, "synthetic-first");
        var bytes = File.ReadAllBytes(path);
        using (new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            try
            {
                vault.SaveRefreshToken(Key, "synthetic-second");
                throw new InvalidOperationException("A held vault file reported a successful commit.");
            }
            catch (IOException) { }
        }
        Check(bytes.AsSpan().SequenceEqual(File.ReadAllBytes(path)), "A failed commit changed the vault.");
        Check(Directory.GetFiles(Path.GetDirectoryName(path)!, "*.tmp").Length == 0, "A failed commit left a temporary file.");
        Console.WriteLine("PASS Windows vault stuck commit stays a bounded failure without change");
        return Task.CompletedTask;
    }

    // Waiting must not outlive the caller's ownership of the credential.
    private static Task LostOwnershipStopsAWaitingCommit(string path)
    {
        var vault = new WindowsTokenVault(path);
        var stamp = vault.SaveRefreshTokenWithRetirement(Key, "synthetic-first");
        var owned = true;
        var holder = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        var disown = After(200, () => Volatile.Write(ref owned, false));
        bool cleared;
        try { cleared = vault.TryClearRetirement(stamp, () => Volatile.Read(ref owned)); }
        finally { holder.Dispose(); }
        disown.Join();
        Check(!cleared, "A commit continued after its owner changed.");
        Check(vault.LoadRefreshToken(Key) == "synthetic-first", "A disowned commit removed the credential.");
        Console.WriteLine("PASS Windows vault waiting commit stops when ownership is lost");
        return Task.CompletedTask;
    }

    // The case that matters to a user: the server has rotated the refresh token,
    // so a momentarily busy lease must not drop the only copy of its successor.
    private static async Task RotationSurvivesAContendedLease(string path)
    {
        var endpoint = new Uri("http://127.0.0.1:1/");
        var options = new ScmOAuthOptions("synthetic-scm", endpoint, endpoint, endpoint,
            "test-client", "test-resource", "profile.read", "/callback");
        var vault = new WindowsTokenVault(path);
        vault.SaveRefreshToken(Key, "synthetic-original");
        Thread? release = null;
        var handler = new Handler(request =>
        {
            if (release is null)
            {
                var lease = HoldLease(path);
                release = After(300, lease.Dispose);
                return new(HttpStatusCode.OK)
                {
                    Content = new StringContent("{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-rotated\",\"token_type\":\"Bearer\",\"expires_in\":3600}",
                        Encoding.UTF8, "application/json")
                };
            }
            return new(HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}", Encoding.UTF8, "application/json") };
        });
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new WindowsTokenVault(path), options);
        try { await oauth.TryRestoreSessionAsync(default); }
        catch (Exception error) when (error is not IOException) { }
        release?.Join();
        Check(release is not null, "Restore never reached the token endpoint.");
        Check(vault.LoadRefreshToken(Key) == "synthetic-rotated", "A busy lease lost the rotated refresh token.");
        Console.WriteLine("PASS Windows vault keeps a rotated refresh token through a busy lease");
    }

    // File.Replace kept the target's DACL; the overwriting move must not widen it.
    private static Task CommitKeepsATightenedDacl(string path)
    {
        var vault = new WindowsTokenVault(path);
        vault.SaveRefreshToken(Key, "synthetic-first");
        vault.SaveRefreshToken(Key, "synthetic-default");
        var inherited = new FileInfo(path).GetAccessControl();
        Check(!inherited.AreAccessRulesProtected &&
            inherited.GetAccessRules(true, false, typeof(System.Security.Principal.SecurityIdentifier)).Count == 0,
            "A commit turned the default inherited permissions into explicit ones.");
        var user = System.Security.Principal.WindowsIdentity.GetCurrent().User!;
        var tight = new FileSecurity();
        tight.SetAccessRuleProtection(true, false);
        tight.AddAccessRule(new FileSystemAccessRule(user, FileSystemRights.FullControl, AccessControlType.Allow));
        new FileInfo(path).SetAccessControl(tight);
        vault.SaveRefreshToken(Key, "synthetic-second");
        var kept = new FileInfo(path).GetAccessControl();
        var rules = kept.GetAccessRules(true, true, typeof(System.Security.Principal.SecurityIdentifier));
        Check(kept.AreAccessRulesProtected && rules.Count == 1 && rules[0].IdentityReference == user,
            "A commit widened the credential vault's access rules.");
        Check(vault.LoadRefreshToken(Key) == "synthetic-second", "A tightened vault lost the commit.");
        Console.WriteLine("PASS Windows vault commit keeps a tightened DACL");
        return Task.CompletedTask;
    }

    // No timers: the holder refuses the first move, and the only call to current
    // after that (the sixth) stands in for a writer that ignores the lease. Retrying
    // must not overwrite what it never compared.
    private static Task OutsideChangeDuringAWaitStopsTheCommit(string path)
    {
        var vault = new WindowsTokenVault(path);
        var stamp = vault.SaveRefreshTokenWithRetirement(Key, "synthetic-first");
        var outside = Encoding.UTF8.GetBytes(Encoding.UTF8.GetString(File.ReadAllBytes(path)).TrimEnd('}') + ",\"synthetic-outside\":\"x\"}");
        var holder = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        var calls = 0;
        bool cleared;
        try
        {
            cleared = vault.TryClearRetirement(stamp, () =>
            {
                if (++calls == 6)
                {
                    File.WriteAllBytes(path, outside);
                    holder.Dispose();
                }
                return true;
            });
        }
        finally { holder.Dispose(); }
        Check(calls >= 6, "The first move was not refused, so no retry ran.");
        Check(!cleared && outside.AsSpan().SequenceEqual(File.ReadAllBytes(path)), "A waiting commit overwrote an outside change.");
        Console.WriteLine("PASS Windows vault waiting commit re-compares the file on disk");
        return Task.CompletedTask;
    }

    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            Task.FromResult(respond(request));
    }
}
