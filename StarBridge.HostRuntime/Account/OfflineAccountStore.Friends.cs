using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal enum OfflineFriendsReadOutcome { Abandoned, Success, Transient, Rejected, ConfirmedWrite, Unchanged }
internal sealed class OfflineFriendsReadLease(BridgeAccountContext owner, BridgeAccountContext? storageOwner,
    string id, string epoch, Semaphore signal, Func<bool> current, OfflineFriendsDisplay? display = null) : IDisposable
{
    internal BridgeAccountContext Owner { get; } = owner;
    internal BridgeAccountContext? StorageOwner { get; } = storageOwner;
    internal string Epoch { get; } = epoch;
    internal string Id { get; } = id;
    private OfflineFriendsDisplay? _display = display;
    internal OfflineFriendsDisplay? Display => _display;
    internal bool Current => Volatile.Read(ref _disposed) == 0 && current();
    private int _finished;
    private int _disposed;
    internal bool Finish() => Interlocked.Exchange(ref _finished, 1) == 0;
    public void Dispose() { if (Interlocked.Exchange(ref _disposed, 1) == 0) { _display = null; signal.Dispose(); } }
}
internal sealed record OfflineFriendsDisplay(FriendsView Directory, DateTimeOffset CachedAtUtc,
    string Version, BridgeAccountContext? StorageOwner, string Epoch);

internal sealed partial class OfflineAccountStore
{
    private string FriendsPath => Path.Combine(Path.GetDirectoryName(_path)!, "friends-v1.bin");
    private string FriendsPolicyPath => Path.Combine(Path.GetDirectoryName(_path)!, "friends-policy-v1.bin");
    private static readonly byte[] FriendsEntropy = Encoding.UTF8.GetBytes("StarBridge.offline-account.friends.v1");
    private static readonly byte[] FriendsPolicyEntropy = Encoding.UTF8.GetBytes("StarBridge.offline-account.friends-policy.v1");
    private const int FriendsLimit = 4 * 1024 * 1024;
    private sealed record FriendDisplayRow(string Callsign, string GameId, string Relationship, DateTimeOffset UpdatedAt);
    private sealed record FriendsDocument(int SchemaVersion, BridgeAccountContext Owner, BridgeAccountContext? StorageOwner,
        string Version, DateTimeOffset CachedAtUtc, DateTimeOffset RefreshedAt, FriendDisplayRow[] Friends,
        FriendDisplayRow[] Incoming, FriendDisplayRow[] Outgoing, FriendDisplayRow[] Blocked);
    private sealed record FriendsPolicy(int SchemaVersion, BridgeAccountContext Owner, BridgeAccountContext? StorageOwner,
        string Epoch, string? AllowedVersion, string? CandidateVersion, string[] Pending, string? LatestReadId);

    // The small durable policy closes publication before remote IO. A crash or
    // failed refusal write therefore cannot leave an old directory eligible.
    internal OfflineFriendsReadLease? BeginFriendsRead(BridgeAccountContext owner, Func<bool> current, bool captureDisplay = false)
    {
        if (!current()) return null;
        using var writer = FriendsWriter();
        var account = Read();
        if (account is null || account.Owner != owner || account.OfflineRevision is not null || !current()) return null;
        FriendsPolicy? old;
        try { old = ReadFriendsPolicy(); }
        catch (Exception error) when (error is IOException or CryptographicException or JsonException or ArgumentException)
        { old = null; }
        var sameOwner = old?.Owner == owner && old.StorageOwner == account.StorageOwner;
        var active = sameOwner ? old!.Pending.Where(FriendsReadAlive).ToArray() : [];
        var lost = sameOwner && active.Length != old!.Pending.Length;
        var candidate = sameOwner && !lost ? old!.CandidateVersion : null;
        if (active.Length >= 64) throw new IOException("Friends display read limit reached.");
        var epoch = sameOwner && !lost ? old!.Epoch : Guid.NewGuid().ToString("N");
        OfflineFriendsDisplay? display = null;
        // Capture under the same writer admission, before this read closes the
        // durable publication gate. Never reuse a candidate from pending IO.
        if (captureDisplay && sameOwner && !lost && active.Length == 0)
            try { display = ReadSelectedFriends(owner, current); }
            catch (Exception error) when (error is IOException or CryptographicException or JsonException or ArgumentException) { }
        var id = Guid.NewGuid().ToString("N");
        var signal = new Semaphore(0, 1, FriendsReadSignalName(id), out var created);
        var lease = new OfflineFriendsReadLease(owner, account.StorageOwner, id, epoch, signal, current, display);
        try
        {
            if (!created) throw new IOException("Friends display read identity collision.");
            if (WriteFriendsPolicy(new(1, owner, account.StorageOwner, epoch, null, candidate, [.. active, id], id), current)) return lease;
            lease.Dispose();
            return null;
        }
        catch { lease.Dispose(); throw; }
    }

    internal bool IsFriendsDisplayCurrent(OfflineFriendsReadLease lease, Func<bool> current)
    {
        if (!current() || !lease.Current || lease.Display is null) return false;
        var account = Read();
        var policy = ReadFriendsPolicy();
        return account?.Owner == lease.Owner && account.StorageOwner == lease.StorageOwner && account.OfflineRevision is null &&
            policy?.Owner == lease.Owner && policy.StorageOwner == lease.StorageOwner && policy.Epoch == lease.Epoch &&
            policy.Pending.Contains(lease.Id) && current() && lease.Current;
    }

    internal void CompleteFriendsRead(OfflineFriendsReadLease lease, OfflineFriendsReadOutcome outcome,
        FriendsView? result, Func<bool> current)
    {
        if (!lease.Finish()) return;
        try
        {
            if (!current()) return;
            using var writer = FriendsWriter();
            var account = Read();
            if (account is null || account.Owner != lease.Owner || account.StorageOwner != lease.StorageOwner ||
                account.OfflineRevision is not null || !current()) return;
            var policy = ReadFriendsPolicy();
            if (policy?.Owner != lease.Owner || policy.StorageOwner != lease.StorageOwner || !policy.Pending.Contains(lease.Id)) return;
            var pending = policy.Pending.Where(id => id != lease.Id).ToArray();
            if (!lease.Current) outcome = OfflineFriendsReadOutcome.Abandoned;
            if (outcome is OfflineFriendsReadOutcome.Rejected or OfflineFriendsReadOutcome.Abandoned)
            {
                policy = new(1, lease.Owner, lease.StorageOwner, Guid.NewGuid().ToString("N"), null, null, pending, null);
                if (!WriteFriendsPolicy(policy, current)) return;
                Safe(FriendsPath);
                if (File.Exists(FriendsPath)) File.Delete(FriendsPath);
                return;
            }
            var candidate = policy.CandidateVersion;
            // A confirmed command result is newer than reads already started
            // before its acknowledgement. It still cannot cross a refusal epoch.
            var confirmedWrite = outcome == OfflineFriendsReadOutcome.ConfirmedWrite;
            if ((outcome == OfflineFriendsReadOutcome.Success || confirmedWrite) && policy.Epoch == lease.Epoch &&
                (confirmedWrite || policy.LatestReadId == lease.Id))
            {
                if (result is null || result.Query is not null || result.Results.Length != 0 || result.RefreshedAt is not { } refreshed)
                    throw new InvalidDataException();
                FriendDisplayRow[] Rows(FriendView[] source) => source.Select(row =>
                    new FriendDisplayRow(row.Callsign, row.GameId, row.Relationship, row.UpdatedAt)).ToArray();
                var document = new FriendsDocument(1, lease.Owner, lease.StorageOwner, Guid.NewGuid().ToString("N"),
                    DateTimeOffset.UtcNow, refreshed, Rows(result.Friends), Rows(result.Incoming), Rows(result.Outgoing), Rows(result.Blocked));
                ValidateFriends(document);
                if (!PublishProtectedBytes(FriendsPath, JsonSerializer.SerializeToUtf8Bytes(document, Json), FriendsEntropy, FriendsLimit,
                    () => current() && lease.Current)) return;
                candidate = document.Version;
                if (confirmedWrite) policy = policy with { LatestReadId = lease.Id };
            }
            WriteFriendsPolicy(policy with { Pending = pending, CandidateVersion = candidate,
                AllowedVersion = pending.Length == 0 ? candidate : null }, current);
        }
        finally { lease.Dispose(); }
    }

    internal OfflineFriendsDisplay? ReadSelectedFriends(BridgeAccountContext owner, Func<bool> current)
    {
        if (!current()) return null;
        var account = Read();
        if (account is null || account.Owner != owner || account.OfflineRevision is not null) return null;
        var policy = ReadFriendsPolicy();
        if (policy?.Owner != owner || policy.StorageOwner != account.StorageOwner || policy.AllowedVersion is null) return null;
        var clear = ReadProtectedBytes(FriendsPath, FriendsEntropy, FriendsLimit);
        if (clear is null) return null;
        FriendsDocument data;
        try { data = JsonSerializer.Deserialize<FriendsDocument>(clear, Json) ?? throw new InvalidDataException(); }
        finally { CryptographicOperations.ZeroMemory(clear); }
        ValidateFriends(data);
        var after = Read();
        var afterPolicy = ReadFriendsPolicy();
        if (data.Owner != owner || data.StorageOwner != account.StorageOwner || data.Version != policy.AllowedVersion ||
            after?.Owner != owner || after.StorageOwner != account.StorageOwner || after.OfflineRevision is not null ||
            afterPolicy?.Owner != owner || afterPolicy.StorageOwner != policy.StorageOwner || afterPolicy.Epoch != policy.Epoch ||
            afterPolicy.AllowedVersion != policy.AllowedVersion || afterPolicy.Pending.Length != 0 || !current()) return null;
        FriendView[] Rows(FriendDisplayRow[] rows) => rows.Select(row =>
            new FriendView(row.Callsign, row.GameId, row.Relationship, null, row.UpdatedAt)).ToArray();
        return new(new(null, data.RefreshedAt, Rows(data.Friends), Rows(data.Incoming), Rows(data.Outgoing), Rows(data.Blocked), []),
            data.CachedAtUtc, data.Version, data.StorageOwner, policy.Epoch);
    }

    // The full directory was already decrypted and validated once. Subsequent
    // pages fence that immutable copy against the small durable publication
    // policy, without reopening the multi-megabyte friends data file.
    internal bool IsSelectedFriendsVersionCurrent(BridgeAccountContext owner, BridgeAccountContext? storageOwner,
        string version, string epoch, Func<bool> current)
    {
        if (!current()) return false;
        var account = Read();
        var policy = ReadFriendsPolicy();
        return account?.Owner == owner && account.StorageOwner == storageOwner && account.OfflineRevision is null &&
            policy?.Owner == owner && policy.StorageOwner == storageOwner && policy.Epoch == epoch &&
            policy.AllowedVersion == version && policy.Pending.Length == 0 && current();
    }

    internal void ClearFriends(BridgeAccountContext owner, Func<bool> current)
    {
        if (!current()) return;
        using var writer = FriendsWriter();
        var account = Read();
        if (account?.Owner != owner || !current()) return;
        var policy = new FriendsPolicy(1, owner, account.StorageOwner, Guid.NewGuid().ToString("N"), null, null, [], null);
        if (!WriteFriendsPolicy(policy, current)) return;
        Safe(FriendsPath);
        if (current() && File.Exists(FriendsPath)) File.Delete(FriendsPath);
    }

    private FileStream FriendsWriter()
    {
        Safe(_path); Safe(_path + ".lock"); Safe(FriendsPath); Safe(FriendsPolicyPath);
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        return new(_path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }
    private FriendsPolicy? ReadFriendsPolicy()
    {
        var clear = ReadProtectedBytes(FriendsPolicyPath, FriendsPolicyEntropy, 16384);
        if (clear is null) return null;
        try
        {
            var policy = JsonSerializer.Deserialize<FriendsPolicy>(clear, Json) ?? throw new InvalidDataException();
            if (policy.SchemaVersion != 1 || !Guid.TryParseExact(policy.Epoch, "N", out _) || policy.Pending is null ||
                policy.Pending.Length > 64 || policy.Pending.Distinct(StringComparer.Ordinal).Count() != policy.Pending.Length ||
                policy.Pending.Any(id => !Guid.TryParseExact(id, "N", out _)) ||
                policy.AllowedVersion is { } version && (!Guid.TryParseExact(version, "N", out _) || policy.Pending.Length != 0 || policy.CandidateVersion != version) ||
                policy.CandidateVersion is { } candidate && !Guid.TryParseExact(candidate, "N", out _) ||
                policy.LatestReadId is { } latest && !Guid.TryParseExact(latest, "N", out _)) throw new InvalidDataException();
            return policy;
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
    }
    private bool WriteFriendsPolicy(FriendsPolicy policy, Func<bool> current) => PublishProtectedBytes(
        FriendsPolicyPath, JsonSerializer.SerializeToUtf8Bytes(policy, Json), FriendsPolicyEntropy, 16384, current);
    private string FriendsReadSignalName(string id) => "Local\\StarBridge.FriendsDisplay." +
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(_path.ToUpperInvariant())))[..24] + "." + id;
    private bool FriendsReadAlive(string id)
    {
        if (!Guid.TryParseExact(id, "N", out _)) return false;
        try { if (Semaphore.TryOpenExisting(FriendsReadSignalName(id), out var signal)) { signal.Dispose(); return true; } }
        catch (WaitHandleCannotBeOpenedException) { }
        return false;
    }
    private static void ValidateFriends(FriendsDocument data)
    {
        if (data.SchemaVersion != 1 || !Guid.TryParseExact(data.Version, "N", out _) ||
            data.CachedAtUtc <= DateTimeOffset.UnixEpoch || data.CachedAtUtc > DateTimeOffset.UtcNow.AddMinutes(5) ||
            data.Friends is null || data.Incoming is null || data.Outgoing is null || data.Blocked is null) throw new InvalidDataException();
        var groups = new[] { (data.Friends, "friend"), (data.Incoming, "incoming"), (data.Outgoing, "outgoing"), (data.Blocked, "blocked") };
        foreach (var (rows, relation) in groups)
            if (rows.Length > 2000 || rows.Any(row => row is null || row.Callsign is null || row.GameId is null ||
                row.Callsign.Length > 512 || row.GameId.Length > 512 || row.Callsign.Any(char.IsControl) || row.GameId.Any(char.IsControl) ||
                row.Relationship != relation && row.Relationship != "unknown")) throw new InvalidDataException();
    }
}
