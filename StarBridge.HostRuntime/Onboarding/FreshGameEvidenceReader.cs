using System.Security.Cryptography;
using System.Text;
using StarBridge.Core.Parsing;
using StarBridge.HostRuntime.Presence;
using static StarBridge.HostRuntime.Presence.CheckedGameLogAccess;

namespace StarBridge.HostRuntime.Onboarding;

internal sealed record FreshGameEvidenceResult(string State, string? Handle = null,
    DateTimeOffset? ObservedAt = null, string? EvidenceStamp = null);

// Explicit, bounded reads only. No live watcher, account context or publication.
internal sealed class FreshGameEvidenceReader(Func<GameProcessSession>? processProbe = null, TimeProvider? time = null)
{
    private readonly Func<GameProcessSession> _probe = processProbe ?? GameLogIdentityReader.Probe;
    private readonly TimeProvider _clock = time ?? TimeProvider.System;
    private static readonly UTF8Encoding Utf8 = new(false, true);

    internal string CheckSelection(string logPath, string version)
    {
        var path = LocalGameEvidenceValidation.SelectionPath(logPath, version);
        using var guard = PinnedDirectories.Open(Path.GetDirectoryName(path)!, () => { });
        if (Exists(path))
        {
            using var file = OpenChecked(path, directory: false, readContent: false);
            Describe(file, path);
        }
        return path;
    }

    internal LocalGameEvidenceBaseline Capture(string logPath, string version, CancellationToken cancellation = default)
    {
        var path = LocalGameEvidenceValidation.SelectionPath(logPath, version);
        var before = _probe();
        var at = _clock.GetUtcNow();
        var budget = new Budget(_clock, cancellation);
        using var guard = PinnedDirectories.Open(Path.GetDirectoryName(path)!, budget.Check);
        var process = Matches(before, path, at) ? before : null;
        var processKey = process is null ? null : SessionKey(process);
        if (!Exists(path))
        {
            budget.Check();
            if (Exists(path) || process is not null && !SameSession(process, _probe(), path, _clock.GetUtcNow()))
                throw new LocalFirstUseException("firstUse.evidence_changed");
            return new(at, null, 0, null, processKey, process?.StartedAt);
        }
        using var handle = OpenChecked(path, directory: false, readContent: true);
        using var file = new FileStream(handle, FileAccess.Read, 16 * 1024);
        var stamp = Describe(handle, path);
        if (stamp.Length > LocalGameEvidenceValidation.MaximumFileBytes) throw new LocalFirstUseException("firstUse.evidence_limit");
        var identity = PersistentIdentity(handle);
        var hash = Hash(file, stamp.Length, budget.Check);
        var repeat = Hash(file, stamp.Length, budget.Check);
        if (stamp != Describe(handle, path) || hash != repeat || identity != PersistentIdentity(handle))
            throw new LocalFirstUseException("firstUse.evidence_changed");
        var after = _probe();
        if (process is not null && !SameSession(process, after, path, _clock.GetUtcNow()))
            throw new LocalFirstUseException("firstUse.evidence_changed");
        budget.Check();
        return new(at, identity, stamp.Length, hash, processKey, process?.StartedAt);
    }

    internal FreshGameEvidenceResult ReadCurrent(string logPath, string version, CancellationToken cancellation = default)
    {
        var now = _clock.GetUtcNow();
        var process = _probe();
        if (!Matches(process, logPath, now)) return new(process.State == "unknown" ? "processUnknown" : "notRunning");
        return Read(logPath, version, new(process.StartedAt!.Value, null, 0, null,
            SessionKey(process), process.StartedAt), cancellation);
    }

    internal FreshGameEvidenceResult Read(string logPath, string version, LocalGameEvidenceBaseline baseline,
        CancellationToken cancellation = default)
    {
        try
        {
            var path = LocalGameEvidenceValidation.SelectionPath(logPath, version);
            var now = _clock.GetUtcNow();
            if (!LocalGameEvidenceValidation.Baseline(baseline, now)) return new("clockChanged");
            var process = _probe();
            if (!Matches(process, path, now)) return new(process.State == "unknown" ? "processUnknown" : "notRunning");
            var budget = new Budget(_clock, cancellation);
            using var guard = PinnedDirectories.Open(Path.GetDirectoryName(path)!, budget.Check);
            if (!Exists(path)) return new("waiting");
            using var handle = OpenChecked(path, directory: false, readContent: true);
            using var file = new FileStream(handle, FileAccess.Read, 16 * 1024);
            var stamp = Describe(handle, path);
            var identity = PersistentIdentity(handle);
            if (stamp.Length > LocalGameEvidenceValidation.MaximumFileBytes) return new("limit");
            var newProcess = process.StartedAt >= baseline.CapturedAt &&
                (baseline.ProcessSessionKey is null || SessionKey(process) != baseline.ProcessSessionKey || baseline.FileIdentity is null);
            var start = baseline.FileIdentity == identity && !newProcess ? baseline.Cursor : 0;
            if (start > stamp.Length) return new("changed");
            if (start > 0 && Hash(file, start, budget.Check) != baseline.PrefixHash) return new("changed");
            var skipPartial = false;
            if (start > 0)
            {
                file.Position = start - 1;
                skipPartial = file.ReadByte() is not ((int)'\r') and not ((int)'\n');
            }
            file.Position = start;
            using var bytes = new Buffers();
            using var digest = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            var candidates = new Dictionary<(string Handle, string Id), LocalGameIdentityRecord>();
            var used = 0;
            var first = start == 0;
            var afterCr = false;
            var invalid = false;
            var quit = false;
            var remaining = stamp.Length - start;
            while (remaining > 0)
            {
                budget.Check();
                var read = file.Read(bytes.Block, 0, (int)Math.Min(remaining, bytes.Block.Length));
                if (read == 0) return new("changed");
                remaining -= read;
                digest.AppendData(bytes.Block.AsSpan(0, read));
                for (var i = 0; i < read; i++)
                {
                    var value = bytes.Block[i];
                    if (afterCr && value == '\n') { afterCr = false; continue; }
                    afterCr = false;
                    if (value is (byte)'\r' or (byte)'\n')
                    {
                        budget.Check();
                        if (!skipPartial)
                        {
                            var lineBytes = bytes.Line.AsSpan(0, used);
                            if (first && lineBytes.StartsWith("\uFEFF"u8)) lineBytes = lineBytes[3..];
                            var line = Utf8.GetString(lineBytes);
                            var state = LocalGameIdentityLine.Parse(line, now, out var record);
                            // A rotated/new-session read may include older records. A
                            // well-timed old damaged identity is not current uncertainty;
                            // damaged/future/unknown record times still fail closed.
                            if (state == LocalGameIdentityLineState.Invalid)
                                invalid |= !LocalGameIdentityLine.TryTimestamp(line, now, out var invalidAt, out var invalidResolution) ||
                                    LocalGameIdentityLine.MeetsSessionTime(new("", "", invalidAt) { ResolutionTicks = invalidResolution },
                                        baseline.CapturedAt, process.StartedAt!.Value, now);
                            if (record is not null && LocalGameIdentityLine.MeetsSessionTime(record,
                                baseline.CapturedAt, process.StartedAt!.Value, now))
                            {
                                var key = (record.Handle.ToLowerInvariant(), record.PlayerId);
                                if (candidates.TryGetValue(key, out var old))
                                { if (record.ObservedAt > old.ObservedAt) candidates[key] = record; }
                                else if (candidates.Count < 2) candidates.Add(key, record);
                            }
                            // A quit is not identity evidence; a current reader must not
                            // resurrect a candidate before it. Conservative even if malformed.
                            if (line.Contains("<SystemQuit>", StringComparison.OrdinalIgnoreCase) &&
                                line.Contains("CSystem::Quit", StringComparison.OrdinalIgnoreCase))
                            {
                                if (!LocalGameIdentityLine.TryTimestamp(line, now, out var quitAt, out var resolution)) invalid = true;
                                else quit |= LocalGameIdentityLine.MeetsSessionTime(
                                    new("", "", quitAt) { ResolutionTicks = resolution },
                                    baseline.CapturedAt, process.StartedAt!.Value, now);
                            }
                        }
                        skipPartial = false; first = false; used = 0; afterCr = value == '\r';
                    }
                    else if (!skipPartial)
                    {
                        if (used == bytes.Line.Length) return new("limit");
                        bytes.Line[used++] = value;
                    }
                }
            }
            var tailHash = Convert.ToHexString(digest.GetHashAndReset());
            if (stamp != Describe(handle, path) || identity != PersistentIdentity(handle) ||
                (start > 0 && Hash(file, start, budget.Check) != baseline.PrefixHash) ||
                Hash(file, stamp.Length - start, budget.Check, start) != tailHash ||
                stamp != Describe(handle, path)) return new("changed");
            var after = _probe();
            if (!SameSession(process, after, path, _clock.GetUtcNow())) return new("processChanged");
            budget.Check();
            if (used != 0 || skipPartial) return new("incomplete");
            if (invalid || candidates.Count > 1) return new("conflict");
            if (quit || candidates.Count == 0) return new("waiting");
            var candidate = candidates.Single().Value;
            // Stable semantic evidence, not a nonce changed by unrelated game log appends.
            var evidence = identity + SessionKey(process) + candidate.Handle.ToLowerInvariant() +
                candidate.PlayerId + candidate.ObservedAt.UtcTicks;
            return new("candidate", candidate.Handle, candidate.ObservedAt, TextHash(evidence));
        }
        catch (OperationCanceledException) { return new("cancelled"); }
        catch (LocalFirstUseException error) when (error.Code == "firstUse.evidence_limit") { return new("limit"); }
        catch (LocalFirstUseException) { return new("unsafe"); }
        catch (GameplayTimeException) { return new("unsafe"); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or DecoderFallbackException or
            ArgumentException or NotSupportedException or System.Security.SecurityException) { return new("unavailable"); }
    }

    internal static bool Matches(GameProcessSession process, string path, DateTimeOffset now) =>
        process.State == "running" && process.LogPath is not null && process.StartedAt is { } started &&
        started.Offset == TimeSpan.Zero && started >= DateTimeOffset.UnixEpoch && started <= now &&
        process.SessionId is { Length: > 0 and <= 256 } && !process.SessionId.Any(char.IsControl) &&
        process.LogPath.Equals(path, StringComparison.OrdinalIgnoreCase);
    internal static string SessionKey(GameProcessSession process) => TextHash(process.SessionId!);
    private static bool SameSession(GameProcessSession before, GameProcessSession after, string path, DateTimeOffset now) =>
        Matches(after, path, now) && before.StartedAt == after.StartedAt && before.SessionId == after.SessionId;
    private static bool Exists(string path)
    {
        try
        {
            if ((File.GetAttributes(path) & (FileAttributes.ReparsePoint | FileAttributes.Directory)) != 0)
                throw new LocalFirstUseException("firstUse.source_invalid");
            return true;
        }
        catch (Exception error) when (error is FileNotFoundException or DirectoryNotFoundException) { return false; }
    }
    private static string TextHash(string text)
    {
        var bytes = Utf8.GetBytes(text);
        try { return Convert.ToHexString(SHA256.HashData(bytes)); }
        finally { CryptographicOperations.ZeroMemory(bytes); }
    }
    private static string Hash(FileStream stream, long length, Action check, long start = 0)
    {
        stream.Position = start;
        var bytes = new byte[16 * 1024];
        using var digest = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        try
        {
            while (length > 0)
            {
                check();
                var read = stream.Read(bytes, 0, (int)Math.Min(length, bytes.Length));
                if (read == 0) throw new IOException();
                digest.AppendData(bytes.AsSpan(0, read)); length -= read;
            }
            return Convert.ToHexString(digest.GetHashAndReset());
        }
        finally { CryptographicOperations.ZeroMemory(bytes); }
    }
    private sealed class Buffers : IDisposable
    {
        internal byte[] Block { get; } = new byte[16 * 1024];
        internal byte[] Line { get; } = new byte[64 * 1024];
        public void Dispose() { CryptographicOperations.ZeroMemory(Block); CryptographicOperations.ZeroMemory(Line); }
    }
    private sealed class Budget(TimeProvider clock, CancellationToken cancellation)
    {
        private readonly long _start = clock.GetTimestamp();
        internal void Check()
        {
            cancellation.ThrowIfCancellationRequested();
            if (clock.GetElapsedTime(_start) >= TimeSpan.FromSeconds(15))
                throw new LocalFirstUseException("firstUse.evidence_limit");
        }
    }
}
