using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

internal static class ScmProfileCacheStorageTests
{
    private static readonly AccountRouteIdentity Owner = AccountRouteIdentity.Create("test", "synthetic", "opaque-owner", null);
    private static readonly ScmSelfProfileContract Profile = new("opaque-owner", "Synthetic pilot", null, "not-cached@example.invalid", "en-US", "UTC");
    private static readonly DateTimeOffset Stamp = DateTimeOffset.UtcNow.AddMinutes(-1);
    private static string PathFor(string root) => Path.Combine(root, "scm-profile-cache", Owner.CacheNamespace[8..] + ".json");
    private static void Check(bool value, string message) { if(!value) throw new InvalidOperationException(message); }

    internal static Task Storage()
    {
        using var f = new Fixture();
        var cache = new ScmProfileCacheStore(f.Root);
        cache.Save(Owner, Profile, Stamp);
        var path = PathFor(f.Root); var folder = Path.GetDirectoryName(path)!;
        var original = File.ReadAllBytes(path);
        using(File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read)) {
            try { cache.Save(Owner, Profile with { Locale = "zh-CN" }, Stamp.AddSeconds(1)); throw new Exception("Locked destination write succeeded"); }
            catch(Exception error) when(error is IOException or UnauthorizedAccessException) { }
        }
        Check(!Directory.GetFiles(folder, "*.tmp").Any(), "Failed atomic replacement leaked its temporary profile data");
        Check(File.ReadAllBytes(path).SequenceEqual(original), "Failed replacement damaged the previous committed file");
        using (var reader = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete)) {
            cache.Save(Owner, Profile with { Locale = "zh-CN" }, Stamp.AddSeconds(1));
            var retained = new byte[(int)reader.Length]; reader.ReadExactly(retained);
            Check(retained.SequenceEqual(original), "Atomic publication changed an existing complete reader's bytes");
            Check(cache.Load(Owner)?.Locale == "zh-CN", "New readers did not observe the newly committed complete profile");
        }
        var other = AccountRouteIdentity.Create("another-environment", "synthetic", "opaque-owner", null);
        cache.Save(other, Profile, Stamp);
        var orphan = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        File.WriteAllText(orphan, "synthetic interrupted own write");
        File.WriteAllText(path + ".tmp", "synthetic legacy own temporary");
        var unrelated = Path.Combine(folder, "unrelated.tmp"); File.WriteAllText(unrelated, "keep");
        Check(cache.Clear(Owner), "Clear must report actual removed cache content");
        Check(!File.Exists(orphan) && !File.Exists(path + ".tmp"), "Explicit clear retained this owner's abandoned temporary files");
        Check(File.ReadAllText(unrelated) == "keep" && cache.Load(other) is not null, "Clear touched another owner or unowned file");
        Check(!cache.Clear(Owner), "Cleared cache must be idempotent");
        return Task.CompletedTask;
    }

    internal static Task OwnerAndBounds()
    {
        using var f = new Fixture();
        var cache = new ScmProfileCacheStore(f.Root);
        cache.Save(Owner, Profile, Stamp);
        var path = PathFor(f.Root);
        var original = File.ReadAllBytes(path);
        var json = File.ReadAllText(path);
        File.WriteAllText(path, json.Replace("opaque-owner", "OPAQUE-OWNER"));
        Check(cache.Load(Owner) is null, "Opaque subjects must not compare case-insensitively");
        File.WriteAllText(path, original.Length > 0 ? System.Text.Encoding.UTF8.GetString(original) : "{}");
        try { cache.Save(Owner, Profile with { Subject = "OPAQUE-OWNER" }, Stamp); throw new Exception("Case-variant subject was saved under another owner key"); }
        catch(InvalidOperationException) { }
        File.WriteAllText(path, json.Replace("\"Environment\":\"TEST\"", "\"Environment\":null"));
        Check(cache.Load(Owner) is null, "Null owner metadata must be an invalid cache, not a crash");
        File.WriteAllText(path, json.Insert(1, "\"SchemaVersion\":1,"));
        Check(cache.Load(Owner) is null, "Duplicate cache metadata must be rejected");
        var fields = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json)!;
        fields.Remove("CachedAtUtc");
        File.WriteAllText(path, JsonSerializer.Serialize(fields));
        Check(cache.Load(Owner) is null, "Cache without an observation time must not invent a synchronization date");
        File.WriteAllText(path, json + new string(' ', 70 * 1024));
        Check(cache.Load(Owner) is null, "Oversized disk data must not be read as an unbounded cache");
        File.WriteAllBytes(path, original);
        try { cache.Save(Owner, Profile with { DisplayName = new string('x', 70 * 1024) }, Stamp); throw new Exception("Oversized profile cache was persisted"); }
        catch(InvalidDataException) { }
        Check(File.ReadAllBytes(path).SequenceEqual(original), "Rejected oversized cache changed existing data");
        try { cache.Save(Owner, Profile, default); throw new Exception("Missing observation time was persisted"); }
        catch (InvalidDataException) { }
        return Task.CompletedTask;
    }

    internal static async Task Processes()
    {
        using var f = new Fixture();
        var cache = new ScmProfileCacheStore(f.Root);
        cache.Save(Owner, Profile, Stamp);
        var path = PathFor(f.Root); var original = File.ReadAllBytes(path);
        using(var worker = Start("hold", f.Root)) {
            try {
                Check(await worker.StandardOutput.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(10)) == "ready:" + worker.Id, "Independent writer did not acquire its lease in the expected process");
                Check(cache.Load(Owner)?.DisplayName == Profile.DisplayName, "An active writer must not block reading the last complete cache");
                try { cache.Clear(Owner); throw new Exception("Clear crossed an active writer lease"); } catch(IOException) { }
                try { cache.Save(Owner, Profile, Stamp.AddSeconds(1)); throw new Exception("Competing writer crossed the independent process lease"); } catch(IOException) { }
                Check(File.ReadAllBytes(path).SequenceEqual(original), "Competing operation changed the committed cache");
                Check(Directory.GetFiles(Path.GetDirectoryName(path)!, "*.tmp").Length == 1, "Clear deleted or changed another process's active temporary file");
            }
            finally {
                await worker.StandardInput.WriteLineAsync("release");
                await worker.StandardInput.FlushAsync();
                await worker.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(10));
            }
            Check(worker.ExitCode == 0, await worker.StandardError.ReadToEndAsync());
        }
        var workers = Enumerable.Range(0, 4).Select(_ => Start("write", f.Root)).ToArray();
        var saved = 0;
        try {
            await Task.WhenAll(workers.Select(async worker => {
                var stdout = worker.StandardOutput.ReadToEndAsync(); var stderr = worker.StandardError.ReadToEndAsync();
                await worker.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(15));
                Check(worker.ExitCode == 0, await stderr);
                var report = await stdout;
                Check(report.StartsWith("done:") && int.TryParse(report[5..].Trim(), out _), "Unexpected independent writer output");
                Interlocked.Add(ref saved, int.Parse(report[5..].Trim()));
            }));
            Check(saved > 0, "All independent writers were busy; no actual concurrent write was verified");
            Check(cache.Load(Owner) is not null, "Independent concurrent writes left a corrupt cache");
            Check(!Directory.GetFiles(Path.GetDirectoryName(path)!, "*.tmp").Any(), "Independent completed writers leaked temporary data");
        } finally { foreach(var worker in workers) worker.Dispose(); }
    }

    internal static async Task InterruptedWriter()
    {
        using var f = new Fixture();
        var cache = new ScmProfileCacheStore(f.Root);
        cache.Save(Owner, Profile, Stamp);
        var path = PathFor(f.Root);
        using (var worker = Start("hold", f.Root)) {
            try {
                Check(await worker.StandardOutput.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(10)) == "ready:" + worker.Id, "Interrupted writer did not acquire its lease in the expected process");
            } finally {
                if (!worker.HasExited) worker.Kill();
                // Exit-code observation can precede kernel handle rundown after
                // Kill. Wait on actual process termination before asserting that
                // its writer lease and interrupted operation file are recoverable.
                Check(worker.WaitForExit(10_000), "Interrupted writer did not physically exit");
            }
        }
        Check(cache.Load(Owner)?.DisplayName == Profile.DisplayName, "Interrupted write damaged the last committed profile");
        Check(Directory.GetFiles(Path.GetDirectoryName(path)!, "*.tmp").Length == 1, "Actual interrupted process did not leave the expected owned operation file");
        Check(cache.Clear(Owner), "Explicit clear did not recover after an interrupted writer");
        Check(cache.Load(Owner) is null && !Directory.GetFiles(Path.GetDirectoryName(path)!, "*.tmp").Any(), "Explicit clear retained interrupted owner data");
    }

    private static Process Start(string mode, string root)
    {
        var info = new ProcessStartInfo("dotnet") { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach(var value in new[] { Assembly.GetExecutingAssembly().Location, "--profile-cache-storage-worker", mode, root }) info.ArgumentList.Add(value);
        return Process.Start(info) ?? throw new IOException("Synthetic cache process did not start");
    }
    internal static async Task<int> Worker(string mode, string root)
    {
        var full = Path.GetFullPath(root);
        var temporary = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if(!full.StartsWith(temporary, StringComparison.OrdinalIgnoreCase) || !Path.GetFileName(full).StartsWith("starbridge-cache-storage-", StringComparison.Ordinal) || !Directory.Exists(full)) return 2;
        var path = PathFor(full);
        if(mode == "hold") {
            using var lease = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var ownTemporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try {
                using var output = new FileStream(ownTemporary, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                output.WriteByte(1); output.Flush(true);
                Console.WriteLine("ready:" + Environment.ProcessId); await Console.Out.FlushAsync();
                if(await Console.In.ReadLineAsync() != "release") return 3;
            } finally { File.Delete(ownTemporary); }
        } else if(mode == "write") {
            var cache = new ScmProfileCacheStore(full); var saved = 0;
            for(var i = 0; i < 24; i++) {
                try { cache.Save(Owner, Profile with { DisplayName = "Synthetic writer " + Environment.ProcessId }, DateTimeOffset.UtcNow); saved++; }
                catch(IOException) { }
            }
            Console.WriteLine("done:" + saved);
        } else return 2;
        return 0;
    }
    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Directory.CreateTempSubdirectory("starbridge-cache-storage-").FullName;
        public void Dispose()
        {
            var target = Path.GetFullPath(Root);
            var temporary = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if(!target.StartsWith(temporary, StringComparison.OrdinalIgnoreCase) || !Path.GetFileName(target).StartsWith("starbridge-cache-storage-", StringComparison.Ordinal)) throw new IOException("Unsafe synthetic cache cleanup path");
            Directory.Delete(target, true);
        }
    }
}
