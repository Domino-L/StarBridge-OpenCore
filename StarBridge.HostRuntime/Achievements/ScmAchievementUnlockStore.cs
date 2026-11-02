using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

// Account-local acknowledgement only; never grants an SCM achievement.
internal sealed class ScmAchievementUnlockStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "scm-achievement-unlocks-v1");
    internal sealed record PendingUnlock(string Receipt, ScmAchievementItem Item);
    internal sealed record State(int SchemaVersion, string OwnerHash, DateOnly[] TriggerDates, string[] Confirmed,
        PendingUnlock[]? Pending = null, string[]? Accepted = null);
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    // The receiving queue commits acceptance before it admits a card. This is
    // separate from the producer removing Pending, so a lost acknowledgement
    // cannot cause a second admission after process or account reconstruction.
    internal bool TryAccept(BridgeAccountContext owner, string receipt, Func<bool> current)
    {
        if (!current()) throw new OperationCanceledException();
        using var lease = Open(owner); var state = lease.Read();
        if ((state.Accepted ?? []).Contains(receipt, StringComparer.Ordinal)) return false;
        if (!(state.Pending ?? []).Any(p => p.Receipt == receipt)) throw new InvalidDataException("Unknown celebration receipt.");
        lease.Save(state with { Accepted = [.. state.Accepted ?? [], receipt] }, current);
        return true;
    }
    internal void ConfirmOffline(BridgeAccountContext owner, ScmAchievementCatalog catalog, Func<bool> current)
    {
        catalog.Validate();
        if (!current()) return;
        using var lease = Open(owner); var state = lease.Read();
        lease.Save(state with { Confirmed = state.Confirmed.Concat(catalog.Items.Where(i => i.Unlocked).Select(i => i.Id))
            .Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray() }, current);
    }
    internal Lease Open(BridgeAccountContext owner)
    {
        if (!owner.IsComplete) throw new InvalidDataException();
        var hash = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(
            new[] { owner.Environment, owner.Authority, owner.Subject })));
        Check(_directory, true); Directory.CreateDirectory(_directory);
        var path = Path.Combine(_directory, hash + ".json");
        Check(path + ".lock", false);
        return new(path, hash, new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None));
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
                new ScmAchievementCatalog(1, DateTimeOffset.UtcNow, pending.Select(p => p.Item).ToArray()).Validate();
            }
            return state;
        }
        internal void Save(State state, Func<bool> current)
        {
            _ = Read(); // Never overwrite a damaged acknowledgement as an empty account.
            var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                if (!current()) throw new OperationCanceledException();
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                { stream.Write(JsonSerializer.SerializeToUtf8Bytes(state, Json)); stream.Flush(true); }
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
