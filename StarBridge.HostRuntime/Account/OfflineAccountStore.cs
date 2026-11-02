using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

// Display only: never an authentication, entitlement or achievement receipt.
internal sealed record OfflineAccountDisplay(string DisplayName, DateTimeOffset CachedAtUtc,
    string? AvatarImageData = null, DateTimeOffset? AvatarCachedAtUtc = null);
internal sealed record OfflineAchievementDisplay(Achievements.AchievementSnapshot Collection, DateTimeOffset CachedAtUtc);
internal sealed record OfflinePersonalProfileDisplay(JsonElement Payload, DateTimeOffset CachedAtUtc);
internal sealed record OfflineProfileData(Profiles.LocalProfileSnapshot? Local, OfflinePersonalProfileDisplay? Remote);
internal sealed partial class OfflineAccountStore(string root)
{
    private readonly string _path = Path.Combine(Path.GetFullPath(root), "offline-account-v1", "snapshot.bin");
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("StarBridge.offline-account.v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 16 };
    private const int Limit = 2 * 1024 * 1024;
    private sealed record Document(int SchemaVersion, BridgeAccountContext Owner, string DisplayName,
        DateTimeOffset CachedAtUtc, long? OfflineRevision, BridgeAccountContext? StorageOwner = null,
        OfflineAchievementDisplay? Achievements = null, OfflinePersonalProfileDisplay? Profile = null,
        Auth.ScmCredentialRetirementStamp? OfflineCredential = null,
        Achievements.ScmAchievementCatalog? ScmAchievements = null);

    internal void Observe(BridgeAccountContext owner, string displayName, Func<bool> current,
        BridgeAccountContext? storageOwner = null)
    {
        if (string.IsNullOrWhiteSpace(displayName) || displayName.Length > 256) return;
        Write(old => new(1, owner, displayName, DateTimeOffset.UtcNow, null, storageOwner,
            old?.Owner == owner ? old.Achievements : null, old?.Owner == owner ? old.Profile : null,
            ScmAchievements: old?.Owner == owner ? old.ScmAchievements : null), current);
    }

    internal void ObserveAchievements(BridgeAccountContext owner, Achievements.AchievementSnapshot snapshot, Func<bool> current)
    {
        snapshot.Validate();
        // Copy mutable collections before persistence. Only confirmed remote snapshots
        // reach this method; the pending evidence outbox is never a display source.
        var copy = new Achievements.AchievementSnapshot(1, new(snapshot.EarnedAt),
            snapshot.Progress is null ? null : new(snapshot.Progress));
        Write(old => old?.Owner == owner && old.OfflineRevision is null
            ? old with { Achievements = new(copy, DateTimeOffset.UtcNow) } : old, current);
    }

    internal void ObserveScmAchievements(BridgeAccountContext owner, Achievements.ScmAchievementCatalog catalog, Func<bool> current)
    {
        catalog.Validate();
        var copy = catalog.Copy();
        // A complete SCM result replaces its source only, including revocations.
        Write(old => old?.Owner == owner && old.OfflineRevision is null
            ? old with { ScmAchievements = copy } : old, current);
    }

    internal Action<BridgeAccountContext, Achievements.ScmAchievementCatalog, Func<bool>>? ScmAchievementsRead { get; set; }
    internal Achievements.ScmAchievementCatalog? ReadSelectedScmAchievements(BridgeAccountContext owner, Func<bool> current)
    {
        var catalog = ReadSelected(owner, current, value => value.ScmAchievements);
        if (catalog is not null && current()) ScmAchievementsRead?.Invoke(owner, catalog, current);
        return current() ? catalog : null;
    }

    internal Achievements.ScmAchievementCatalog? ReadScmAchievements(long revision)
    {
        var value = Read();
        if (value?.OfflineRevision != revision || value.ScmAchievements is not { } catalog) return null;
        bool Current() => Read()?.OfflineRevision == revision;
        ScmAchievementsRead?.Invoke(value.Owner, catalog, Current);
        return Current() ? catalog : null;
    }

    internal OfflineAchievementDisplay? ReadAchievements(long revision)
    {
        var value = Read();
        return value?.OfflineRevision == revision ? value.Achievements : null;
    }

    internal void ClearAchievements(BridgeAccountContext owner, Func<bool> current) =>
        Write(old => old?.Owner == owner ? old with { Achievements = null } : old, current);

    // Only a completed offline transaction can select this exact account for
    // cold reading. An old file cannot be reused under another mode revision.
    internal void Pin(BridgeAccountContext owner, long revision, Func<bool> current,
        Auth.ScmCredentialRetirementStamp? credential = null) =>
        Write(old => old?.Owner == owner ? old with { OfflineRevision = revision, OfflineCredential = credential } : old, current);

    // Native-only selection. A mode/cache owner alone does not prove that the
    // original login is still retained. No vault discovery outside known roots.
    internal BridgeAccountContext? ReadRetainedOwner(long revision, Func<bool> current)
    {
        if (!current()) return null;
        var value = Read();
        if (value?.OfflineRevision != revision || value.OfflineCredential is not { } credential) return null;
        Auth.WindowsTokenVault.ValidateRetirementStamp(credential);
        var ownerHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
            value.Owner.Authority + ":" + value.Owner.Subject)));
        if (credential.OwnerKey != ownerHash || credential.EntriesHash is null || credential.ActiveEntryHash is null) return null;
        foreach (var name in new[] { "scm-token-vault.json", "scm-token-vault.development.json", "scm-token-vault.local.json" })
        {
            var vault = new Auth.WindowsTokenVault(Path.Combine(root, name));
            if (vault.IsRetirementBoundTo(credential))
                return vault.IsRetirementCurrent(credential) && current() ? value.Owner : null;
        }
        return null;
    }

    internal void ReturnToOffline(long previousRevision, long revision, Func<bool> current) =>
        Write(old => old?.OfflineRevision == previousRevision ? old with { OfflineRevision = revision } : old, current);

    internal OfflineAccountDisplay? ReadDisplay(long revision)
    {
        var value = Read();
        return value?.OfflineRevision == revision ? Display(value) : null;
    }

    internal OfflineAccountDisplay? ReadSelectedDisplay(BridgeAccountContext owner, Func<bool> current)
        => ReadSelectedDisplayOwner(owner, current)?.Display;

    internal (OfflineAccountDisplay Display, BridgeAccountContext? StorageOwner)? ReadSelectedDisplayOwner(
        BridgeAccountContext owner, Func<bool> current)
    {
        if (!current()) return null;
        var value = Read();
        return value?.Owner == owner && value.OfflineRevision is null && current()
            ? (Display(value), value.StorageOwner) : null;
    }

    internal Hangar.LocalHangarSnapshot? ReadSelectedHangar(BridgeAccountContext owner, Func<bool> current) =>
        ReadSelected(owner, current, value => value.StorageOwner is { } storage
            ? new Hangar.LocalHangarStore(root).Read(storage) : null);

    internal OfflineProfileData? ReadSelectedProfile(BridgeAccountContext owner, Func<bool> current) =>
        ReadSelected(owner, current, value => new OfflineProfileData(value.StorageOwner is { } storage
            ? new Profiles.LocalPersonalProfileStore(root).Read(storage) : null, value.Profile));

    internal OfflineAchievementDisplay? ReadSelectedAchievements(BridgeAccountContext owner, Func<bool> current) =>
        ReadSelected(owner, current, value => value.Achievements);

    private T? ReadSelected<T>(BridgeAccountContext owner, Func<bool> current, Func<Document, T?> read) where T : class
    {
        if (!current()) return null;
        var value = Read();
        if (value?.Owner != owner || value.OfflineRevision is not null || !current()) return null;
        var result = read(value);
        return current() ? result : null;
    }

    internal Hangar.LocalHangarSnapshot? ReadHangar(long revision)
    {
        var value = Read();
        if (value?.OfflineRevision != revision || value.StorageOwner is not { } owner) return null;
        // Reuse the existing durable file, not an imported copy or a remote fallback.
        // This store instance has no resolver, writer, sampler or sync owner attached.
        return new Hangar.LocalHangarStore(root).Read(owner);
    }

    internal Profiles.LocalProfileSnapshot? ReadProfile(long revision)
    {
        var value = Read();
        if (value?.OfflineRevision != revision || value.StorageOwner is not { } owner) return null;
        return new Profiles.LocalPersonalProfileStore(root).Read(owner);
    }

    private Document? Read()
    {
        var clear = ReadProtectedBytes(_path, Entropy, Limit);
        if (clear is null) return null;
        try
        {
            if (clear.Length > Limit) throw new InvalidDataException();
            var data = JsonSerializer.Deserialize<Document>(clear, Json);
            if (data is null || data.SchemaVersion != 1 || data.Owner is null ||
                string.IsNullOrWhiteSpace(data.Owner.Environment) || string.IsNullOrWhiteSpace(data.Owner.Authority) ||
                string.IsNullOrWhiteSpace(data.Owner.Subject) || string.IsNullOrWhiteSpace(data.DisplayName) ||
                data.DisplayName.Length > 256 || data.CachedAtUtc > DateTimeOffset.UtcNow.AddMinutes(5))
                throw new InvalidDataException();
            if (data.Achievements is { } achievements)
            {
                if (achievements.Collection is null || achievements.CachedAtUtc <= DateTimeOffset.UnixEpoch ||
                    achievements.CachedAtUtc > DateTimeOffset.UtcNow.AddMinutes(5)) throw new InvalidDataException();
                achievements.Collection.Validate();
            }
            data.ScmAchievements?.Validate();
            if (data.Profile is { } profile && (profile.CachedAtUtc <= DateTimeOffset.UnixEpoch ||
                profile.CachedAtUtc > DateTimeOffset.UtcNow.AddMinutes(5) ||
                profile.Payload.ValueKind != JsonValueKind.Object || profile.Payload.GetRawText().Length > 1024 * 1024 ||
                !profile.Payload.TryGetProperty("editable", out var editable) || editable.ValueKind != JsonValueKind.False))
                throw new InvalidDataException();
            return data;
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
    }

    private void Write(Func<Document?, Document?> update, Func<bool> current)
    {
        Safe(_path); Safe(_path + ".lock");
        if (!current()) return;
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        using var writer = new FileStream(_path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        if (!current()) return;
        var old = Read(); var next = update(old);
        if (next is null || next == old) return;
        PublishProtectedBytes(_path, JsonSerializer.SerializeToUtf8Bytes(next, Json), Entropy, Limit, current);
    }

    private static void Safe(string path)
    {
        for (string? node = path; node is not null; node = Path.GetDirectoryName(node))
        {
            try { if ((File.GetAttributes(node) & FileAttributes.ReparsePoint) != 0) throw new IOException(); }
            catch (FileNotFoundException) { }
            catch (DirectoryNotFoundException) { }
        }
    }
}
