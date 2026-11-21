using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

// Account-local acknowledgement only; never grants an SCM achievement.
internal sealed class ScmAchievementUnlockStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "scm-achievement-unlocks-v1");
    internal sealed record PendingUnlock(string Receipt, ScmAchievementItem Item);
    // Accepted: receipts whose card completed its visible dwell (build 105,
    // user 11-21: "不要在加载的时候就已经获取然后不弹庆祝了"). Older builds wrote
    // it at queue admission; those receipts are treated as already shown.
    // Baseline: this account has had a first sync, so later first reads (a new
    // process, an account return, an offline cache) celebrate what is new.
    internal sealed record State(int SchemaVersion, string OwnerHash, DateOnly[] TriggerDates, string[] Confirmed,
        PendingUnlock[]? Pending = null, string[]? Accepted = null, bool? Baseline = null);
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    internal const int MaximumPending = 4096;
    // Stores from builds before the flag kept confirmed IDs only after a sync.
    internal static bool HasBaseline(State state) => state.Baseline == true || state.Confirmed.Length > 0;
    // Pending entries that a receiver has not already shown.
    internal static PendingUnlock[] Unshown(State state) =>
        (state.Pending ?? []).Where(p => !(state.Accepted ?? []).Contains(p.Receipt, StringComparer.Ordinal)).ToArray();
    // Admission check only; nothing is written until the card has been shown.
    // A receipt already shown, or no longer pending, is not admitted again.
    // Called while the delivery holds its lock, so it waits for the file only briefly.
    internal bool CanAdmit(BridgeAccountContext owner, IReadOnlyCollection<string> receipts, Func<bool> current)
    {
        if (!current()) throw new OperationCanceledException();
        using var lease = Open(owner, attempts: 4); var state = lease.Read();
        return Unshown(state).Any(p => receipts.Contains(p.Receipt, StringComparer.Ordinal));
    }
    internal static bool IsSharingViolation(IOException error) => error.HResult == unchecked((int)0x80070020);
    // Only what a card needs; descriptions and conditions are not kept, so a long
    // backlog stays far inside the store's own limits (R1 P2).
    internal static ScmAchievementItem ForCard(ScmAchievementItem item, DateTimeOffset now) => item with {
        Description = null, Condition = null, ImageUrl = null, CurrentValue = null, TargetValue = null,
        UnlockedAtUtc = item.UnlockedAtUtc ?? now };
    // One atomic save after the card's visible dwell: shown, and no longer pending.
    internal void MarkPresented(BridgeAccountContext owner, IReadOnlyCollection<string> receipts, Func<bool> current)
    {
        using var lease = Open(owner); var state = lease.Read();
        var shown = (state.Pending ?? []).Where(p => receipts.Contains(p.Receipt, StringComparer.Ordinal)).Select(p => p.Receipt).ToArray();
        if (shown.Length == 0) return;
        lease.Save(state with {
            Pending = (state.Pending ?? []).Where(p => !shown.Contains(p.Receipt, StringComparer.Ordinal)).ToArray(),
            Accepted = (state.Accepted ?? []).Concat(shown).Distinct(StringComparer.Ordinal).ToArray() }, current);
    }
    // A cached catalog read while offline. After the account's first sync, IDs
    // the account has not seen become pending cards for the next online moment.
    internal void ConfirmOffline(BridgeAccountContext owner, ScmAchievementCatalog catalog, Func<bool> current)
    {
        catalog.Validate();
        if (!current()) return;
        using var lease = Open(owner); var state = lease.Read();
        var baseline = HasBaseline(state);
        var known = state.Confirmed.ToHashSet(StringComparer.Ordinal);
        var added = catalog.Items.Where(i => i.Unlocked).OrderBy(i => i.DisplayOrder).Where(i => known.Add(i.Id)).ToArray();
        var pending = (state.Pending ?? []).ToList();
        if (baseline) pending.AddRange(added.Select(i => new PendingUnlock(state.OwnerHash + ":" + i.Id, ForCard(i, DateTimeOffset.UtcNow))));
        lease.Save(state with { Confirmed = known.Order(StringComparer.Ordinal).ToArray(), Pending = pending.ToArray(), Baseline = true }, current);
    }
    internal Lease Open(BridgeAccountContext owner, int attempts = 40)
    {
        if (!owner.IsComplete) throw new InvalidDataException();
        var hash = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(
            new[] { owner.Environment, owner.Authority, owner.Subject })));
        Check(_directory, true); Directory.CreateDirectory(_directory);
        var path = Path.Combine(_directory, hash + ".json");
        Check(path + ".lock", false);
        // Build 105: a shown card's acknowledgement writes from the receiver's
        // side, so a short wait for the other holder replaces failing outright.
        for (var attempt = 0; ; attempt++)
        {
            try { return new(path, hash, new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None)); }
            catch (IOException error) when (IsSharingViolation(error) && attempt < attempts) { Thread.Sleep(25); }
        }
    }
    internal sealed class Lease(string path, string hash, FileStream fileLock) : IDisposable
    {
        internal State Read()
        {
            if (!Check(path, false)) return new(1, hash, [], []);
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is <= 0 or > 8 * 1024 * 1024) throw new InvalidDataException();
            var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
            using var document = JsonDocument.Parse(bytes);
            Profiles.LocalPersonalProfileStore.RejectDuplicates(document.RootElement);
            var state = JsonSerializer.Deserialize<State>(bytes, Json);
            Validate(state, hash);
            return state!;
        }
        // Shared by Read and Save, so a state that Read would reject is never
        // written over a readable file (R2 P2).
        private static void Validate(State? state, string hash)
        {
            if (state is null || state.SchemaVersion != 1 || state.OwnerHash != hash || state.Confirmed is null || state.TriggerDates is null ||
                state.TriggerDates.Distinct().Count() != state.TriggerDates.Length ||
                state.Confirmed.Any(id => !ScmAchievementPresentation.ValidId(id)) ||
                state.Confirmed.Distinct(StringComparer.Ordinal).Count() != state.Confirmed.Length)
                throw new InvalidDataException();
            if (state.Accepted is { } accepted &&
                (accepted.Any(r => !state.Confirmed.Any(id => r == hash + ":" + id)) ||
                    accepted.Distinct(StringComparer.Ordinal).Count() != accepted.Length))
                throw new InvalidDataException();
            if (state.Pending is { } pending)
            {
                if (pending.Any(p => p is null || p.Item is null || !p.Item.Unlocked || !state.Confirmed.Contains(p.Item.Id) ||
                    p.Receipt != hash + ":" + p.Item.Id) || pending.Select(p => p.Receipt).Distinct().Count() != pending.Length)
                    throw new InvalidDataException();
                // A backlog is not one SCM page: each card is checked on its own and
                // the queue has its own cap, inside the 8 MiB file limit (R2 P2).
                if (pending.Length > MaximumPending) throw new InvalidDataException();
                foreach (var entry in pending) new ScmAchievementCatalog(1, DateTimeOffset.UtcNow, [entry.Item]).Validate();
            }
        }
        internal void Save(State state, Func<bool> current)
        {
            _ = Read(); // Never overwrite a damaged acknowledgement as an empty account.
            Validate(state, hash);
            var encoded = JsonSerializer.SerializeToUtf8Bytes(state, Json);
            if (encoded.Length > 8 * 1024 * 1024) throw new InvalidDataException();
            var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                if (!current()) throw new OperationCanceledException();
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                { stream.Write(encoded); stream.Flush(true); }
                Check(Path.GetDirectoryName(path)!, true); var exists = Check(path, false);
                if (!current()) throw new OperationCanceledException();
                if (exists) File.Replace(temporary, path, null); else File.Move(temporary, path);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
        public void Dispose() => fileLock.Dispose();
    }
    private static bool Check(string path, bool directory)
    {
        FileAttributes attributes;
        try { attributes = File.GetAttributes(path); }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
        if (attributes.HasFlag(FileAttributes.ReparsePoint) || attributes.HasFlag(FileAttributes.Directory) != directory)
            throw new IOException();
        return true;
    }
}
