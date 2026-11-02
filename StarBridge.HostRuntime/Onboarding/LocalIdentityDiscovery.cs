using System.Security.Cryptography;
using System.Text;
using StarBridge.Core.Parsing;
using StarBridge.HostRuntime.Presence;
using static StarBridge.HostRuntime.Presence.CheckedGameLogAccess;

namespace StarBridge.HostRuntime.Onboarding;

// Internal scan receipt only. Paths, hashes and numeric player IDs are never a wire contract.
internal sealed record LocalIdentityDiscoveryResult(string State, bool ScopeChecked = false,
    string? Handle = null, DateTimeOffset? ObservedAt = null, string? ScopeStamp = null,
    LocalGameEvidenceBaseline? Baseline = null);

/// <summary>
/// Identity-only discovery in a selected installation/version. No account, journal,
/// publication, gameplay time import or profile write. A candidate from this scan
/// is historical, including records inside Game.log; it is never a new-session receipt.
/// A later owner must re-scan/revalidate before explicit confirmation.
/// </summary>
internal sealed class LocalIdentityDiscovery(TimeProvider? timeProvider = null)
{
    private const int MaximumArchives = 512;
    private const long MaximumFileBytes = 64L * 1024 * 1024;
    private const long MaximumTotalBytes = 256L * 1024 * 1024;
    private static readonly TimeSpan TimeBudget = TimeSpan.FromSeconds(15);
    private static readonly UTF8Encoding Utf8 = new(false, true);
    private readonly TimeProvider _clock = timeProvider ?? TimeProvider.System;

    internal LocalIdentityDiscoveryResult Scan(string gameLogPath, string version,
        CancellationToken cancellation = default)
    {
        var started = _clock.GetTimestamp();
        void Check()
        {
            cancellation.ThrowIfCancellationRequested();
            if (_clock.GetElapsedTime(started) >= TimeBudget) throw new DiscoveryFailure("limit");
        }
        var files = new List<OpenedLog>();
        try
        {
            Check();
            if (!OperatingSystem.IsWindows()) return new("unavailable");
            var path = ValidateSelection(gameLogPath, version);
            var directory = Path.GetDirectoryName(path)!;
            using var liveGuard = PinnedDirectories.Open(directory, Check);
            var backups = Path.Combine(directory, "logbackups");
            using var backupGuard = BackupExists(backups) ? PinnedDirectories.Open(backups, Check) : null;
            var names = ListScope(path, backups, backupGuard is not null, Check);
            long total = 0;
            foreach (var name in names)
            {
                Check();
                var handle = OpenChecked(name, directory: false, readContent: true);
                try
                {
                    var stamp = Describe(handle, name);
                    if (stamp.Length > MaximumFileBytes || stamp.Length > MaximumTotalBytes - total)
                        throw new DiscoveryFailure("limit");
                    total += stamp.Length;
                    files.Add(new(name, new FileStream(handle, FileAccess.Read, 16 * 1024), stamp));
                }
                catch { handle.Dispose(); throw; }
            }

            using var buffers = new ScanBuffers();
            using var generation = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            var candidates = new Dictionary<(string Handle, string Id), LocalGameIdentityRecord>();
            var invalid = false;
            var tail = false;
            var now = _clock.GetUtcNow();
            foreach (var file in files)
            {
                Check();
                using var digest = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
                var used = 0;
                var first = true;
                var afterCr = false;
                var remaining = file.Stamp.Length;
                while (remaining > 0)
                {
                    Check();
                    var read = file.Stream.Read(buffers.Block, 0, (int)Math.Min(remaining, buffers.Block.Length));
                    if (read == 0) throw new DiscoveryFailure("changed");
                    digest.AppendData(buffers.Block.AsSpan(0, read));
                    remaining -= read;
                    for (var i = 0; i < read; i++)
                    {
                        var value = buffers.Block[i];
                        if (afterCr && value == (byte)'\n') { afterCr = false; continue; }
                        afterCr = false;
                        if (value is (byte)'\r' or (byte)'\n')
                        {
                            Check();
                            var bytes = buffers.Line.AsSpan(0, used);
                            if (first && bytes.StartsWith("\uFEFF"u8)) bytes = bytes[3..];
                            var state = LocalGameIdentityLine.Parse(Utf8.GetString(bytes), now, out var record);
                            invalid |= state == LocalGameIdentityLineState.Invalid;
                            if (record is not null)
                            {
                                var key = (record.Handle.ToLowerInvariant(), record.PlayerId);
                                if (candidates.TryGetValue(key, out var previous))
                                {
                                    if (record.ObservedAt > previous.ObservedAt) candidates[key] = record;
                                }
                                else if (candidates.Count < 2) candidates.Add(key, record);
                            }
                            first = false;
                            used = 0;
                            afterCr = value == (byte)'\r';
                        }
                        else
                        {
                            if (used == buffers.Line.Length) throw new DiscoveryFailure("limit");
                            buffers.Line[used++] = value;
                        }
                    }
                }
                // Even an ordinary unfinished tail may later become identity evidence.
                tail |= used != 0;
                file.Verify();
                var header = Utf8.GetBytes(file.Path + "\n" + file.Stamp);
                try { generation.AppendData(header); }
                finally { CryptographicOperations.ZeroMemory(header); }
                var hash = digest.GetHashAndReset();
                generation.AppendData(hash);
                file.ContentHash = hash;
            }
            Check();
            // Recheck all open files after reading the whole scope, not just after each file.
            foreach (var file in files)
            {
                Check();
                file.Verify();
                // Metadata alone is not a content snapshot (e.g. an open writer or
                // coarse timestamp filesystem). A second bounded pass checks bytes too.
                file.Stream.Position = 0;
                using var repeat = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
                var remaining = file.Stamp.Length;
                while (remaining > 0)
                {
                    Check();
                    var read = file.Stream.Read(buffers.Block, 0, (int)Math.Min(remaining, buffers.Block.Length));
                    if (read == 0) throw new DiscoveryFailure("changed");
                    remaining -= read;
                    repeat.AppendData(buffers.Block.AsSpan(0, read));
                }
                var hash = repeat.GetHashAndReset();
                try
                {
                    if (!CryptographicOperations.FixedTimeEquals(hash, file.ContentHash!))
                        throw new DiscoveryFailure("changed");
                }
                finally { CryptographicOperations.ZeroMemory(hash); }
                file.Verify();
            }
            if (BackupExists(backups) != (backupGuard is not null) ||
                !names.SequenceEqual(ListScope(path, backups, backupGuard is not null, Check), StringComparer.OrdinalIgnoreCase))
                throw new DiscoveryFailure("changed");
            Check();
            if (tail) return new("incomplete");
            var scopeStamp = Convert.ToHexString(generation.GetHashAndReset());
            var live = files.SingleOrDefault(f => f.Path.Equals(path, StringComparison.OrdinalIgnoreCase));
            var baseline = live is null ? new LocalGameEvidenceBaseline(now, null, 0, null, null, null) :
                new(now, PersistentIdentity(live.Stream.SafeFileHandle), live.Stamp.Length,
                    Convert.ToHexString(live.ContentHash!), null, null);
            if (invalid || candidates.Count > 1) return new("conflict", true, ScopeStamp: scopeStamp, Baseline: baseline);
            if (candidates.Count == 0) return new("missing", true, ScopeStamp: scopeStamp, Baseline: baseline);
            var candidate = candidates.Single().Value;
            return new("candidate", true, candidate.Handle, candidate.ObservedAt, scopeStamp, baseline);
        }
        catch (OperationCanceledException) { return new("cancelled"); }
        catch (DiscoveryFailure error) { return new(error.State); }
        catch (GameplayTimeException) { return new("unsafe"); }
        catch (LocalFirstUseException) { return new("unsafe"); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or System.Security.SecurityException or DecoderFallbackException)
        { return new("unavailable"); }
        finally { foreach (var file in files) file.Dispose(); }
    }

    private static string ValidateSelection(string path, string version)
        => LocalGameEvidenceValidation.SelectionPath(path, version);

    private static bool CurrentExists(string path)
    {
        try
        {
            if ((File.GetAttributes(path) & (FileAttributes.ReparsePoint | FileAttributes.Directory)) != 0)
                throw new DiscoveryFailure("unsafe");
            return true;
        }
        catch (Exception error) when (error is FileNotFoundException or DirectoryNotFoundException) { return false; }
    }

    private static bool BackupExists(string path)
    {
        try
        {
            var attributes = File.GetAttributes(path);
            if ((attributes & FileAttributes.ReparsePoint) != 0 || (attributes & FileAttributes.Directory) == 0)
                throw new DiscoveryFailure("unsafe");
            return true;
        }
        catch (Exception error) when (error is FileNotFoundException or DirectoryNotFoundException) { return false; }
    }

    private static string[] ListScope(string path, string backups, bool exists, Action check)
    {
        var files = new List<string>();
        if (CurrentExists(path)) files.Add(path);
        var archives = 0;
        if (exists)
        {
            var options = new EnumerationOptions { RecurseSubdirectories = false, IgnoreInaccessible = false,
                AttributesToSkip = 0, MatchType = MatchType.Simple, MatchCasing = MatchCasing.CaseInsensitive };
            foreach (var file in Directory.EnumerateFiles(backups, "*.log", options))
            {
                check();
                if (archives++ == MaximumArchives) throw new DiscoveryFailure("limit");
                files.Add(file);
            }
        }
        return files.Order(StringComparer.OrdinalIgnoreCase).ToArray();
    }

    private sealed class OpenedLog(string path, FileStream stream, FileStamp stamp) : IDisposable
    {
        internal string Path { get; } = path;
        internal FileStream Stream { get; } = stream;
        internal FileStamp Stamp { get; } = stamp;
        internal byte[]? ContentHash { get; set; }
        internal void Verify()
        {
            if (Describe(Stream.SafeFileHandle, Path) != Stamp) throw new DiscoveryFailure("changed");
        }
        public void Dispose()
        {
            Stream.Dispose();
            if (ContentHash is { } hash) CryptographicOperations.ZeroMemory(hash);
        }
    }
    private sealed class ScanBuffers : IDisposable
    {
        internal byte[] Block { get; } = new byte[16 * 1024];
        internal byte[] Line { get; } = new byte[64 * 1024];
        public void Dispose()
        {
            CryptographicOperations.ZeroMemory(Block);
            CryptographicOperations.ZeroMemory(Line);
        }
    }
    private sealed class DiscoveryFailure(string state) : Exception
    {
        internal string State { get; } = state;
    }
}
